// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title MockPerpManager
/// @notice Mock PerpManager for SDK integration tests against Anvil.
/// All state is configurable via setter methods so tests can control return values.
contract MockPerpManager {
    // ======================== STRUCTS ========================

    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    struct PerpConfig {
        PoolKey key;
        address creator;
        address vault;
        address beacon;
        address fees;
        address marginRatios;
        address lockupPeriod;
        address sqrtPriceImpactLimit;
    }

    struct MarginRatios {
        uint24 min;
        uint24 max;
        uint24 liq;
    }

    struct MakerDetails {
        uint32 unlockTimestamp;
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        int256 entryCumlFundingBelowX96;
        int256 entryCumlFundingWithinX96;
        int256 entryCumlFundingDivSqrtPWithinX96;
    }

    struct Position {
        bytes32 perpId;
        uint256 margin;
        int256 entryPerpDelta;
        int256 entryUsdDelta;
        int256 entryCumlFundingX96;
        uint256 entryCumlBadDebtX96;
        uint256 entryCumlUtilizationX96;
        MarginRatios marginRatios;
        MakerDetails makerDetails;
    }

    struct OpenTakerPosParams {
        address holder;
        bool isLong;
        uint128 margin;
        uint24 marginRatio;
        uint128 unspecifiedAmountLimit;
    }

    struct OpenMakerPosParams {
        address holder;
        uint128 margin;
        uint120 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint128 maxAmt0In;
        uint128 maxAmt1In;
    }

    struct ClosePositionParams {
        uint256 posId;
        uint128 minAmt0Out;
        uint128 minAmt1Out;
        uint128 maxAmt1In;
    }

    struct CreatePerpParams {
        address beacon;
        address fees;
        address marginRatios;
        address lockupPeriod;
        address sqrtPriceImpactLimit;
        uint256 startingSqrtPriceX96;
    }

    struct QuoteResult {
        int256 pnl;
        int256 funding;
        uint256 netMargin;
        bool wasLiquidated;
    }

    // ======================== EVENTS ========================

    event PerpCreated(
        bytes32 perpId,
        address beacon,
        uint256 sqrtPriceX96,
        uint256 indexPriceX96
    );

    event PositionOpened(
        bytes32 perpId,
        uint256 sqrtPriceX96,
        uint256 longOI,
        uint256 shortOI,
        uint256 posId,
        bool isMaker,
        int256 perpDelta,
        int256 usdDelta,
        int24 tickLower,
        int24 tickUpper
    );

    event PositionClosed(
        bytes32 perpId,
        uint256 sqrtPriceX96,
        uint256 longOI,
        uint256 shortOI,
        uint256 posId,
        bool wasMaker,
        bool wasLiquidated,
        bool wasPartialClose,
        int256 perpDelta,
        int256 usdDelta,
        int24 tickLower,
        int24 tickUpper
    );

    // ======================== STATE ========================

    uint256 private _nextPositionId = 1;
    uint256 private _nextPerpNonce = 1;
    uint24 public protocolFee = 0;

    // perpId => PerpConfig
    mapping(bytes32 => PerpConfig) private _configs;
    mapping(bytes32 => bool) private _perpExists;

    // perpId => sqrtPriceX96 (for TWAP)
    mapping(bytes32 => uint256) private _sqrtPrices;

    // posId => Position
    mapping(uint256 => Position) private _positions;
    mapping(uint256 => bool) private _positionExists;

    // posId => QuoteResult
    mapping(uint256 => QuoteResult) private _quoteResults;

    // posId => closed
    mapping(uint256 => bool) public closedPositions;

    // ======================== SETUP METHODS ========================

    function setProtocolFee(uint24 fee) external {
        protocolFee = fee;
    }

    function setupPerp(
        bytes32 perpId,
        PoolKey calldata key,
        address creator,
        address vault,
        address beacon,
        address fees,
        address marginRatios,
        address lockupPeriod,
        address sqrtPriceImpactLimit,
        uint256 sqrtPriceX96
    ) external {
        _configs[perpId] = PerpConfig(
            key, creator, vault, beacon, fees, marginRatios, lockupPeriod, sqrtPriceImpactLimit
        );
        _perpExists[perpId] = true;
        _sqrtPrices[perpId] = sqrtPriceX96;
    }

    function setupPosition(
        uint256 posId,
        bytes32 perpId,
        uint128 margin,
        int256 entryPerpDelta,
        int256 entryUsdDelta,
        MarginRatios calldata ratios
    ) external {
        _positions[posId].perpId = perpId;
        _positions[posId].margin = uint256(margin);
        _positions[posId].entryPerpDelta = entryPerpDelta;
        _positions[posId].entryUsdDelta = entryUsdDelta;
        _positions[posId].entryCumlFundingX96 = 0;
        _positions[posId].entryCumlBadDebtX96 = 0;
        _positions[posId].entryCumlUtilizationX96 = 0;
        _positions[posId].marginRatios = ratios;
        // makerDetails stays zero-initialized
        _positionExists[posId] = true;
    }

    function setupQuoteResult(
        uint256 posId,
        int256 pnl,
        int256 funding,
        uint256 netMargin,
        bool wasLiquidated
    ) external {
        _quoteResults[posId] = QuoteResult(pnl, funding, netMargin, wasLiquidated);
    }

    // ======================== VIEW METHODS ========================

    /// @notice Returns config for a perp (matches real PerpManager.cfgs signature)
    function cfgs(bytes32 perpId)
        external
        view
        returns (
            PoolKey memory key,
            address creator,
            address vault,
            address beacon,
            address fees,
            address marginRatios,
            address lockupPeriod,
            address sqrtPriceImpactLimit
        )
    {
        PerpConfig memory cfg = _configs[perpId];
        return (
            cfg.key,
            cfg.creator,
            cfg.vault,
            cfg.beacon,
            cfg.fees,
            cfg.marginRatios,
            cfg.lockupPeriod,
            cfg.sqrtPriceImpactLimit
        );
    }

    /// @notice Returns TWAP sqrtPriceX96 for a perp
    function timeWeightedAvgSqrtPriceX96(bytes32 perpId, uint32 /* lookback */)
        external
        view
        returns (uint256)
    {
        return _sqrtPrices[perpId];
    }

    /// @notice Returns position data (matches real PerpManager.positions signature)
    function positions(uint256 posId)
        external
        view
        returns (
            bytes32 perpId,
            uint256 margin,
            int256 entryPerpDelta,
            int256 entryUsdDelta,
            int256 entryCumlFundingX96,
            uint256 entryCumlBadDebtX96,
            uint256 entryCumlUtilizationX96,
            MarginRatios memory marginRatios,
            MakerDetails memory makerDetails
        )
    {
        Position memory pos = _positions[posId];
        return (
            pos.perpId,
            pos.margin,
            pos.entryPerpDelta,
            pos.entryUsdDelta,
            pos.entryCumlFundingX96,
            pos.entryCumlBadDebtX96,
            pos.entryCumlUtilizationX96,
            pos.marginRatios,
            pos.makerDetails
        );
    }

    /// @notice Quote close position (matches real PerpManager signature)
    function quoteClosePosition(uint256 posId)
        external
        view
        returns (
            bytes memory unexpectedReason,
            int256 pnl,
            int256 funding,
            uint256 netMargin,
            bool wasLiquidated
        )
    {
        if (!_positionExists[posId]) {
            return (abi.encodeWithSignature("Error(string)", "position does not exist"), 0, 0, 0, false);
        }

        QuoteResult memory result = _quoteResults[posId];
        return (bytes(""), result.pnl, result.funding, result.netMargin, result.wasLiquidated);
    }

    // ======================== WRITE METHODS ========================

    /// @notice Create a new perp market
    function createPerp(CreatePerpParams calldata params) external returns (bytes32 perpId) {
        // Generate a deterministic perpId
        perpId = keccak256(abi.encodePacked(block.timestamp, _nextPerpNonce++));

        _perpExists[perpId] = true;
        _sqrtPrices[perpId] = params.startingSqrtPriceX96;

        emit PerpCreated(perpId, params.beacon, params.startingSqrtPriceX96, params.startingSqrtPriceX96);
    }

    /// @notice Open a taker position
    function openTakerPos(bytes32 perpId, OpenTakerPosParams calldata params)
        external
        returns (uint256 posId)
    {
        require(_perpExists[perpId], "perp does not exist");

        posId = _nextPositionId++;

        // Calculate entry deltas from margin and ratio
        uint256 notional = (uint256(params.margin) * 1e6) / uint256(params.marginRatio);
        int256 perpDelta = params.isLong ? int256(notional) : -int256(notional);
        int256 usdDelta = params.isLong ? -int256(notional) : int256(notional);

        _positions[posId].perpId = perpId;
        _positions[posId].margin = uint256(params.margin);
        _positions[posId].entryPerpDelta = perpDelta;
        _positions[posId].entryUsdDelta = usdDelta;
        _positions[posId].marginRatios = MarginRatios(params.marginRatio, 1000000, params.marginRatio / 2);
        _positionExists[posId] = true;

        // Set default quote result (no PnL, margin = deposited margin)
        _quoteResults[posId] = QuoteResult(0, 0, uint256(params.margin), false);

        emit PositionOpened(
            perpId,
            _sqrtPrices[perpId],
            1000, // longOI placeholder
            1000, // shortOI placeholder
            posId,
            false, // isMaker = false
            perpDelta,
            usdDelta,
            -887220, // tickLower placeholder
            887220   // tickUpper placeholder
        );
    }

    /// @notice Open a maker position
    function openMakerPos(bytes32 perpId, OpenMakerPosParams calldata params)
        external
        returns (uint256 posId)
    {
        require(_perpExists[perpId], "perp does not exist");

        posId = _nextPositionId++;

        _positions[posId].perpId = perpId;
        _positions[posId].margin = uint256(params.margin);
        _positions[posId].marginRatios = MarginRatios(100000, 1000000, 50000);
        _positionExists[posId] = true;

        // Set default quote result
        _quoteResults[posId] = QuoteResult(0, 0, uint256(params.margin), false);

        emit PositionOpened(
            perpId,
            _sqrtPrices[perpId],
            1000, // longOI
            1000, // shortOI
            posId,
            true, // isMaker = true
            0,    // perpDelta
            0,    // usdDelta
            params.tickLower,
            params.tickUpper
        );
    }

    /// @notice Close a position
    function closePosition(ClosePositionParams calldata params) external {
        require(_positionExists[params.posId], "position does not exist");

        Position memory pos = _positions[params.posId];
        QuoteResult memory quote = _quoteResults[params.posId];

        closedPositions[params.posId] = true;
        _positionExists[params.posId] = false;

        emit PositionClosed(
            pos.perpId,
            _sqrtPrices[pos.perpId],
            1000, // longOI
            1000, // shortOI
            params.posId,
            false, // wasMaker
            quote.wasLiquidated,
            false, // wasPartialClose
            pos.entryPerpDelta,
            pos.entryUsdDelta,
            -887220, // tickLower
            887220   // tickUpper
        );
    }
}
