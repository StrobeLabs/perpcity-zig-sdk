/// Q96 = 2^96, used for Uniswap V4 sqrtPriceX96 fixed-point format.
pub const Q96: u256 = 1 << 96;

/// 1e6 as a u64, used for USDC 6-decimal scaling.
pub const NUMBER_1E6: u64 = 1_000_000;

/// 1e6 as a u256, for big integer arithmetic.
pub const BIGINT_1E6: u256 = 1_000_000;

/// 1e6 as f64, for floating point conversions.
pub const F64_1E6: f64 = 1_000_000.0;

/// Maximum safe integer for f64 conversion (~2^53).
pub const MAX_SAFE_F64_INT: u64 = 9_007_199_254_740_992;
