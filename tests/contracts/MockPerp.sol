// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

// Struct and event shapes mirror perpcity-contracts v1.0.0 (Structs.sol and
// IPerp.sol) so that solc derives the same selectors and topics the SDK does.

struct OpenMakerParams {
    address holder;
    uint128 margin;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 maxAmt0In;
    uint256 maxAmt1In;
    uint64 deadline;
}

struct OpenTakerParams {
    address holder;
    uint128 margin;
    int256 perpDelta;
    uint256 amt1Limit;
    uint256 maxTotalFee;
    uint64 deadline;
}

struct AdjustMakerParams {
    uint256 posId;
    int128 marginDelta;
    int128 liquidityDelta;
    uint256 amt0Limit;
    uint256 amt1Limit;
    uint64 deadline;
}

struct MoveMakerParams {
    uint256 posId;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 removeAmt0Min;
    uint256 removeAmt1Min;
    uint256 addAmt0Max;
    uint256 addAmt1Max;
    int128 marginDelta;
    uint64 deadline;
}

struct AdjustTakerParams {
    uint256 posId;
    int128 marginDelta;
    int256 perpDelta;
    uint256 amt1Limit;
    uint256 maxTotalFee;
    bool reduceOnly;
    uint64 deadline;
}

struct SwapResult {
    int256 delta;
    uint256 ammPrice;
    int256 totalFeeAmt;
    uint256 lpFeeAmt;
    uint256 protocolFeeAmt;
    uint256 creatorFeeAmt;
    uint256 insuranceFeeAmt;
    uint256 feeFundFeeAmt;
}

struct MakerFunding {
    int256 belowX96;
    int256 withinInventoryX192;
}

struct Maker {
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 lastLpFeeGrowthInsideX128;
    MakerFunding lastCumlFunding;
    int256 lastFundingCorrectionX128;
}

struct Position {
    int256 delta;
    uint128 margin;
    int256 lastCumlFundingX96;
}

struct Taker {
    uint256 lastUtilPaymentsX96;
    uint256 lastReserveUtilPaymentsX96;
}

struct PositionPreview {
    bool isMaker;
    uint256 markPrice;
    int256 settledMargin;
    uint256 pendingLpFees;
    int256 pendingFunding;
    uint256 pendingUtil;
    uint256 pendingReserveUtil;
    uint256 value;
    int256 unrealizedPnl;
    int256 equity;
    bool meetsInitialMargin;
    bool liquidatable;
    bool backstoppable;
    uint256 nominalLiqFee;
    uint256 payableLiqFee;
}

struct OpenInterest {
    uint128 long;
    uint128 short;
}

struct Capacity {
    uint128 long;
    uint128 short;
}

struct Rates {
    int88 fundingPerDay;
    uint64 longUtilFeePerDay;
    uint64 shortUtilFeePerDay;
    uint40 lastTouch;
    uint256 lastMark;
}

struct Modules {
    address beacon;
    address fees;
    address funding;
    address marginRatios;
    address priceImpact;
    address pricing;
}

/// @title MockPerp
/// @notice Minimal per-market Perp shape used by SDK integration tests. It
/// exposes the v1.0.0 function and event signatures the SDK encodes and
/// decodes, and tracks just enough state (owner, margin, size) to read back;
/// it does not run real position math or move USDC.
contract MockPerp {
    error DeadlineExpired();
    error PositionDoesNotExist();
    error NonMakerPosition();
    error NonTakerPosition();
    error ZeroAmount();

    address public immutable owner;
    address public immutable governor;
    address public immutable withdrawalController;
    uint24 public immutable emaWindow;
    uint32 public immutable latency;

    Modules internal _modules;
    uint256 public nextPosId = 1;
    uint256 public protocolFee;
    uint256 public tvlCap = type(uint256).max;

    mapping(uint256 => address) public positionOwner;
    mapping(uint256 => Position) internal _positions;
    mapping(uint256 => Maker) internal _makers;

    OpenInterest internal _oi;
    Capacity internal _cap;
    uint128 internal _totalMargin;

    event MakerOpened(
        uint256 indexed posId,
        address indexed owner,
        int24 tickLower,
        int24 tickUpper,
        uint128 liquidity,
        int256 delta,
        int256 lastCumlFundingX96,
        MakerFunding lastCumlFunding
    );
    event MakerAdjusted(
        uint256 indexed posId,
        address indexed owner,
        int128 marginDelta,
        int128 liquidityDelta,
        int256 funding,
        uint256 lpFees,
        int256 delta,
        uint128 margin,
        uint128 liquidity,
        int256 lastCumlFundingX96,
        MakerFunding lastCumlFunding
    );
    event MakerClosed(
        uint256 indexed posId,
        address indexed owner,
        int128 marginDelta,
        int128 liquidityDelta,
        int256 funding,
        uint256 lpFees,
        int256 delta,
        uint128 margin,
        uint128 liquidity,
        int256 lastCumlFundingX96,
        MakerFunding lastCumlFunding
    );
    event MakerBackstopped(
        uint256 indexed posId,
        uint128 marginIn,
        address posRecipient,
        int256 funding,
        uint256 lpFees,
        uint128 margin,
        int256 delta,
        uint128 liquidity,
        int256 lastCumlFundingX96,
        MakerFunding lastCumlFunding
    );
    event MakerLiquidated(uint256 indexed posId, address indexed feeRecipient, uint128 liquidityAmount, uint256 liqFee);
    event MakerMoved(
        uint256 indexed posId,
        address indexed owner,
        int24 oldTickLower,
        int24 oldTickUpper,
        int24 newTickLower,
        int24 newTickUpper,
        uint128 oldLiquidity,
        uint128 newLiquidity,
        int128 marginDelta,
        int256 funding,
        uint256 lpFees
    );

    event TakerOpened(
        uint256 indexed posId,
        address indexed owner,
        uint128 margin,
        SwapResult sr,
        int256 lastCumlFundingX96
    );
    event TakerAdjusted(
        uint256 indexed posId,
        address indexed owner,
        int128 marginDelta,
        SwapResult sr,
        int256 funding,
        uint256 utilFees,
        int256 delta,
        uint128 margin,
        int256 lastCumlFundingX96
    );
    event TakerClosed(
        uint256 indexed posId,
        address indexed owner,
        int128 marginDelta,
        SwapResult sr,
        int256 funding,
        uint256 utilFees,
        int256 delta,
        uint128 margin,
        int256 lastCumlFundingX96
    );
    event TakerBackstopped(
        uint256 indexed posId,
        uint128 marginIn,
        address posRecipient,
        int256 funding,
        uint256 utilFees,
        int256 delta,
        uint128 margin,
        int256 lastCumlFundingX96
    );
    event TakerLiquidated(uint256 indexed posId, address indexed feeRecipient, uint128 perpAmount, uint256 liqFee);

    event PositionOwnerUpdated(uint256 indexed posId, address indexed oldOwner, address indexed newOwner);
    event Donated(address donor, uint128 amount, uint128 badDebt, uint80 insurance);
    event OpenInterestUpdated(OpenInterest oi);
    event CapacityUpdated(Capacity cap);
    event ProtocolFeeSynced(uint256 protocolFee);

    constructor(
        address owner_,
        address governor_,
        address withdrawalController_,
        Modules memory mods,
        uint24 emaWindow_,
        uint32 latency_
    ) {
        owner = owner_;
        governor = governor_;
        withdrawalController = withdrawalController_;
        _modules = mods;
        emaWindow = emaWindow_;
        latency = latency_;
    }

    modifier checkDeadline(uint64 deadline) {
        require(block.timestamp <= deadline, DeadlineExpired());
        _;
    }

    // ---------------------------------------------------------------- views

    function modules() external view returns (Modules memory) {
        return _modules;
    }

    function positions(uint256 posId) external view returns (Position memory) {
        return _positions[posId];
    }

    function makerDetails(uint256 posId) external view returns (Maker memory) {
        return _makers[posId];
    }

    function takerDetails(uint256) external pure returns (Taker memory) {
        return Taker({ lastUtilPaymentsX96: 0, lastReserveUtilPaymentsX96: 0 });
    }

    function previewPosition(uint256 posId) external view returns (PositionPreview memory p) {
        require(positionOwner[posId] != address(0), PositionDoesNotExist());
        Position memory pos = _positions[posId];
        p.isMaker = _makers[posId].liquidity != 0;
        p.markPrice = 1 << 96;
        p.settledMargin = int256(uint256(pos.margin));
        p.equity = p.settledMargin;
        p.meetsInitialMargin = true;
    }

    function openInterest() external view returns (OpenInterest memory) {
        return _oi;
    }

    function capacity() external view returns (Capacity memory) {
        return _cap;
    }

    function physicalCloseCapacity() external view returns (uint128 longClose, uint128 shortClose) {
        return (_cap.long, _cap.short);
    }

    function accountedTvl() external view returns (uint256) {
        return _totalMargin;
    }

    function solvencyState() external view returns (uint128 badDebt, uint128 totalMargin) {
        return (0, _totalMargin);
    }

    function rates() external view returns (Rates memory) {
        return Rates({
            fundingPerDay: 0,
            longUtilFeePerDay: 0,
            shortUtilFeePerDay: 0,
            lastTouch: uint40(block.timestamp),
            lastMark: 1 << 96
        });
    }

    function poolState() external pure returns (int24 tick, uint160 sqrtPrice, uint256 ammPrice, uint128 liquidity) {
        return (0, uint160(1) << 96, 1 << 96, 1e18);
    }

    // ------------------------------------------------------- test controls

    function setOpenInterest(uint128 long_, uint128 short_) external {
        _oi = OpenInterest({ long: long_, short: short_ });
        emit OpenInterestUpdated(_oi);
    }

    function setCapacity(uint128 long_, uint128 short_) external {
        _cap = Capacity({ long: long_, short: short_ });
        emit CapacityUpdated(_cap);
    }

    // --------------------------------------------------------------- maker

    function openMaker(OpenMakerParams calldata params) external checkDeadline(params.deadline) returns (uint256 posId) {
        posId = nextPosId++;
        positionOwner[posId] = params.holder;
        _positions[posId] = Position({ delta: 0, margin: params.margin, lastCumlFundingX96: 0 });
        _makers[posId].tickLower = params.tickLower;
        _makers[posId].tickUpper = params.tickUpper;
        _makers[posId].liquidity = params.liquidity;
        _totalMargin += params.margin;
        emit PositionOwnerUpdated(posId, address(0), params.holder);
        emit MakerOpened(
            posId,
            params.holder,
            params.tickLower,
            params.tickUpper,
            params.liquidity,
            0,
            0,
            MakerFunding(0, 0)
        );
    }

    function adjustMaker(AdjustMakerParams calldata params) external checkDeadline(params.deadline) {
        Maker storage m = _requireMaker(params.posId);
        m.liquidity = uint128(int128(m.liquidity) + params.liquidityDelta);
        Position storage pos = _positions[params.posId];
        pos.margin = uint128(int128(pos.margin) + params.marginDelta);
        emit MakerAdjusted(
            params.posId,
            positionOwner[params.posId],
            params.marginDelta,
            params.liquidityDelta,
            0,
            0,
            pos.delta,
            pos.margin,
            m.liquidity,
            0,
            MakerFunding(0, 0)
        );
    }

    function moveMaker(MoveMakerParams calldata params) external checkDeadline(params.deadline) {
        Maker storage m = _requireMaker(params.posId);
        emit MakerMoved(
            params.posId,
            positionOwner[params.posId],
            m.tickLower,
            m.tickUpper,
            params.tickLower,
            params.tickUpper,
            m.liquidity,
            params.liquidity,
            params.marginDelta,
            0,
            0
        );
        m.tickLower = params.tickLower;
        m.tickUpper = params.tickUpper;
        m.liquidity = params.liquidity;
    }

    function liquidateMaker(uint256 posId, address liquidationFeeRecipient, uint128 liquidityAmount) external {
        Maker storage m = _requireMaker(posId);
        require(liquidityAmount != 0, ZeroAmount());
        address prevOwner = positionOwner[posId];
        m.liquidity -= liquidityAmount;
        if (m.liquidity == 0) {
            delete positionOwner[posId];
            emit MakerClosed(posId, prevOwner, 0, -int128(liquidityAmount), 0, 0, 0, 0, 0, 0, MakerFunding(0, 0));
            emit PositionOwnerUpdated(posId, prevOwner, address(0));
        } else {
            emit MakerAdjusted(
                posId,
                prevOwner,
                0,
                -int128(liquidityAmount),
                0,
                0,
                0,
                _positions[posId].margin,
                m.liquidity,
                0,
                MakerFunding(0, 0)
            );
        }
        emit MakerLiquidated(posId, liquidationFeeRecipient, liquidityAmount, 0);
    }

    function backstopMaker(
        uint256 posId,
        uint128 marginIn,
        address positionRecipient,
        uint64 deadline
    ) external checkDeadline(deadline) {
        Maker storage m = _requireMaker(posId);
        Position storage pos = _positions[posId];
        pos.margin += marginIn;
        emit MakerBackstopped(
            posId,
            marginIn,
            positionRecipient,
            0,
            0,
            pos.margin,
            pos.delta,
            m.liquidity,
            0,
            MakerFunding(0, 0)
        );
        _reassign(posId, positionRecipient);
    }

    // --------------------------------------------------------------- taker

    function openTaker(OpenTakerParams calldata params) external checkDeadline(params.deadline) returns (uint256 posId) {
        posId = nextPosId++;
        // Bounds-check the narrowing cast before packing the BalanceDelta so
        // the mock matches the on-chain Perp's overflow semantics.
        require(
            params.perpDelta >= type(int128).min && params.perpDelta <= type(int128).max,
            "MockPerp: perpDelta overflow"
        );
        positionOwner[posId] = params.holder;
        _positions[posId] = Position({
            delta: packDelta(int128(params.perpDelta), 0),
            margin: params.margin,
            lastCumlFundingX96: 0
        });
        _totalMargin += params.margin;
        SwapResult memory sr;
        sr.delta = _positions[posId].delta;
        sr.ammPrice = 1 << 96;
        emit PositionOwnerUpdated(posId, address(0), params.holder);
        emit TakerOpened(posId, params.holder, params.margin, sr, 0);
    }

    function adjustTaker(AdjustTakerParams calldata params) external checkDeadline(params.deadline) {
        _requireTaker(params.posId);
        Position storage pos = _positions[params.posId];
        pos.margin = uint128(int128(pos.margin) + params.marginDelta);
        SwapResult memory sr;
        emit TakerAdjusted(params.posId, positionOwner[params.posId], params.marginDelta, sr, 0, 0, pos.delta, pos.margin, 0);
    }

    function liquidateTaker(uint256 posId, address liquidationFeeRecipient, uint128 perpAmount) external {
        _requireTaker(posId);
        require(perpAmount != 0, ZeroAmount());
        address prevOwner = positionOwner[posId];
        SwapResult memory sr;
        delete positionOwner[posId];
        emit TakerClosed(posId, prevOwner, 0, sr, 0, 0, 0, 0, 0);
        emit PositionOwnerUpdated(posId, prevOwner, address(0));
        emit TakerLiquidated(posId, liquidationFeeRecipient, perpAmount, 0);
    }

    function backstopTaker(
        uint256 posId,
        uint128 marginIn,
        address positionRecipient,
        uint64 deadline
    ) external checkDeadline(deadline) {
        _requireTaker(posId);
        Position storage pos = _positions[posId];
        pos.margin += marginIn;
        emit TakerBackstopped(posId, marginIn, positionRecipient, 0, 0, pos.delta, pos.margin, 0);
        _reassign(posId, positionRecipient);
    }

    // ------------------------------------------------------- permissionless

    function touch() external { }

    function donate(uint128 amount) external {
        emit Donated(msg.sender, amount, 0, 0);
    }

    function syncProtocolFee() external {
        emit ProtocolFeeSynced(protocolFee);
    }

    // ------------------------------------------------------------ internal

    function _requireMaker(uint256 posId) internal view returns (Maker storage m) {
        require(positionOwner[posId] != address(0), PositionDoesNotExist());
        m = _makers[posId];
        require(m.liquidity != 0, NonMakerPosition());
    }

    function _requireTaker(uint256 posId) internal view {
        require(positionOwner[posId] != address(0), PositionDoesNotExist());
        require(_makers[posId].liquidity == 0, NonTakerPosition());
    }

    function _reassign(uint256 posId, address newOwner) internal {
        address prevOwner = positionOwner[posId];
        if (prevOwner != newOwner) {
            positionOwner[posId] = newOwner;
            emit PositionOwnerUpdated(posId, prevOwner, newOwner);
        }
    }

    function packDelta(int128 amount0, int128 amount1) internal pure returns (int256) {
        return int256((uint256(uint128(amount0)) << 128) | uint256(uint128(amount1)));
    }
}
