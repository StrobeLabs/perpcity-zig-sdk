// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

struct OpenMakerParams {
    address holder;
    uint128 margin;
    int24 tickLower;
    int24 tickUpper;
    uint128 liquidity;
    uint256 maxAmt0In;
    uint256 maxAmt1In;
}

struct OpenTakerParams {
    address holder;
    uint128 margin;
    int256 perpDelta;
    uint256 amt1Limit;
}

struct AdjustMakerParams {
    uint256 posId;
    int128 marginDelta;
    int128 liquidityDelta;
    uint256 amt0Limit;
    uint256 amt1Limit;
}

struct AdjustTakerParams {
    uint256 posId;
    int128 marginDelta;
    int256 perpDelta;
    uint256 amt1Limit;
}

struct SwapResult {
    int256 delta;
    uint256 ammPrice;
    int256 totalFeeAmt;
    uint256 lpFeeAmt;
    uint256 protocolFeeAmt;
    uint256 creatorFeeAmt;
    uint256 insuranceFeeAmt;
}

struct OpenInterest {
    uint128 long;
    uint128 short;
}

struct Capacity {
    uint128 long;
    uint128 short;
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
/// @notice Minimal per-market Perp shape used by SDK integration tests. Only
/// emits the v0.1.0 events the SDK decodes; does not run real position math.
contract MockPerp {
    address public immutable OWNER;
    Modules public modules_;
    uint256 public nextPosId = 1;
    uint256 public protocolFee;

    struct Position {
        int256 delta;
        uint128 margin;
        uint24 liqMarginRatio;
        uint24 backstopMarginRatio;
        int256 lastCumlFundingX96;
    }

    struct MakerExtra {
        int24 tickLower;
        int24 tickUpper;
        uint128 liquidity;
        bool exists;
    }

    mapping(uint256 => Position) internal _positions;
    mapping(uint256 => MakerExtra) internal _makers;

    OpenInterest internal _oi;
    Capacity internal _cap;

    event MakerOpened(uint256 posId);
    event MakerAdjusted(uint256 posId, int256 funding, uint256 longUtilFees, uint256 shortUtilFees, uint256 lpFees);
    event MakerClosed(
        uint256 posId,
        int256 funding,
        uint256 longUtilFees,
        uint256 shortUtilFees,
        uint256 lpFees,
        uint256 liqFee,
        bool isLiquidation
    );
    event MakerBackstopped(
        uint256 posId,
        uint128 marginIn,
        address posRecipient,
        int256 funding,
        uint256 longUtilFees,
        uint256 shortUtilFees,
        uint256 lpFees
    );

    event TakerOpened(uint256 posId, SwapResult sr);
    event TakerAdjusted(uint256 posId, SwapResult sr, int256 funding, uint256 utilFees);
    event TakerClosed(
        uint256 posId,
        SwapResult sr,
        int256 funding,
        uint256 utilFees,
        uint256 liqFee,
        bool isLiquidation
    );
    event TakerBackstopped(
        uint256 posId,
        uint128 marginIn,
        address posRecipient,
        int256 funding,
        uint256 utilFees
    );

    event Donated(address donor, uint128 amount, uint128 badDebt, uint80 insurance);
    event OpenInterestUpdated(OpenInterest oi);
    event CapacityUpdated(Capacity cap);
    event ProtocolFeeSynced(uint256 protocolFee);

    constructor(address owner, Modules memory mods, uint256 _protocolFee) {
        OWNER = owner;
        modules_ = mods;
        protocolFee = _protocolFee;
    }

    function modules() external view returns (address, address, address, address, address, address) {
        Modules memory m = modules_;
        return (m.beacon, m.fees, m.funding, m.marginRatios, m.priceImpact, m.pricing);
    }

    function positions(uint256 posId)
        external
        view
        returns (int256, uint128, uint24, uint24, int256)
    {
        Position memory p = _positions[posId];
        return (p.delta, p.margin, p.liqMarginRatio, p.backstopMarginRatio, p.lastCumlFundingX96);
    }

    function openInterest() external view returns (uint128, uint128) {
        return (_oi.long, _oi.short);
    }

    function capacity() external view returns (uint128, uint128) {
        return (_cap.long, _cap.short);
    }

    function setOpenInterest(uint128 long_, uint128 short_) external {
        _oi = OpenInterest({long: long_, short: short_});
        emit OpenInterestUpdated(_oi);
    }

    function setCapacity(uint128 long_, uint128 short_) external {
        _cap = Capacity({long: long_, short: short_});
        emit CapacityUpdated(_cap);
    }

    function openMaker(OpenMakerParams calldata params) external returns (uint256 posId) {
        posId = nextPosId++;
        _positions[posId] = Position({
            delta: 0,
            margin: params.margin,
            liqMarginRatio: 50_000,
            backstopMarginRatio: 20_000,
            lastCumlFundingX96: 0
        });
        _makers[posId] = MakerExtra({
            tickLower: params.tickLower,
            tickUpper: params.tickUpper,
            liquidity: params.liquidity,
            exists: true
        });
        emit MakerOpened(posId);
    }

    function adjustMaker(AdjustMakerParams calldata params) external {
        emit MakerAdjusted(params.posId, 0, 0, 0, 0);
    }

    function liquidateMaker(uint256 posId, address) external {
        emit MakerClosed(posId, 0, 0, 0, 0, 0, true);
    }

    function backstopMaker(uint256 posId, uint128 marginIn, address positionRecipient) external {
        emit MakerBackstopped(posId, marginIn, positionRecipient, 0, 0, 0, 0);
    }

    function openTaker(OpenTakerParams calldata params) external returns (uint256 posId) {
        posId = nextPosId++;
        // Bounds-check the narrowing casts before packing the BalanceDelta so
        // the mock matches the on-chain Perp's overflow semantics.
        require(
            params.perpDelta >= type(int128).min && params.perpDelta <= type(int128).max,
            "MockPerp: perpDelta overflow"
        );
        require(params.amt1Limit <= uint256(uint128(type(int128).max)), "MockPerp: amt1Limit overflow");
        int128 amt1 = -int128(int256(params.amt1Limit));
        _positions[posId] = Position({
            delta: packDelta(int128(params.perpDelta), amt1),
            margin: params.margin,
            liqMarginRatio: 50_000,
            backstopMarginRatio: 20_000,
            lastCumlFundingX96: 0
        });
        SwapResult memory sr = SwapResult({
            delta: _positions[posId].delta,
            ammPrice: 0,
            totalFeeAmt: 0,
            lpFeeAmt: 0,
            protocolFeeAmt: 0,
            creatorFeeAmt: 0,
            insuranceFeeAmt: 0
        });
        emit TakerOpened(posId, sr);
    }

    function adjustTaker(AdjustTakerParams calldata params) external {
        SwapResult memory sr = SwapResult({
            delta: 0,
            ammPrice: 0,
            totalFeeAmt: 0,
            lpFeeAmt: 0,
            protocolFeeAmt: 0,
            creatorFeeAmt: 0,
            insuranceFeeAmt: 0
        });
        emit TakerAdjusted(params.posId, sr, 0, 0);
    }

    function liquidateTaker(uint256 posId, address) external {
        SwapResult memory sr;
        emit TakerClosed(posId, sr, 0, 0, 0, true);
    }

    function backstopTaker(uint256 posId, uint128 marginIn, address positionRecipient) external {
        emit TakerBackstopped(posId, marginIn, positionRecipient, 0, 0);
    }

    function donate(uint128 amount) external {
        emit Donated(msg.sender, amount, 0, 0);
    }

    function syncProtocolFee() external {
        emit ProtocolFeeSynced(protocolFee);
    }

    function packDelta(int128 amount0, int128 amount1) internal pure returns (int256) {
        return int256((uint256(uint128(amount0)) << 128) | uint256(uint128(amount1)));
    }
}
