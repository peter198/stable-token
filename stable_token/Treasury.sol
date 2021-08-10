pragma solidity >=0.6.0 <0.8.5;
 
 import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
 import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
 import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
 
 import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
 import "https://github.com/Uniswap/uniswap-lib/blob/master/contracts/libraries/Babylonian.sol";
 import "https://github.com/Uniswap/uniswap-lib/blob/master/contracts/libraries/FullMath.sol";

 //import "deps/npm/chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
 //import "deps/npm/uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
 //import "deps/npm/uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

 //import "lib/uniswap-v2-periphery/IUniswapV2Router02.sol";
 //import "lib/uniswap-lib/FullMath.sol";  
 //import "lib/uniswap-lib/Babylonian.sol";

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint reserveA, uint reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint reserve0, uint reserve1,) = IUniswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint amountA, uint reserveA, uint reserveB) internal pure returns (uint amountB) {
        require(amountA > 0, 'UniswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
        require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint amountInWithFee = amountIn.mul(997);
        uint numerator = amountInWithFee.mul(reserveOut);
        uint denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) internal pure returns (uint amountIn) {
        require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint numerator = reserveIn.mul(amountOut).mul(1000);
        uint denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint amountIn, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        for (uint i; i < path.length - 1; i++) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint amountOut, address[] memory path) internal view returns (uint[] memory amounts) {
        require(path.length >= 2, 'UniswapV2Library: INVALID_PATH');
        amounts = new uint[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint i = path.length - 1; i > 0; i--) {
            (uint reserveIn, uint reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}

// library containing some math for dealing with the liquidity shares of a pair, e.g. computing their exact value
// in terms of the underlying tokens
library UniswapV2LiquidityMathLibrary {
    using SafeMath for uint256;

    // computes the direction and magnitude of the profit-maximizing trade
    function computeProfitMaximizingTrade(
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 reserveA,
        uint256 reserveB
    ) pure internal returns (bool aToB, uint256 amountIn) {
        aToB = FullMath.mulDiv(reserveA, truePriceTokenB, reserveB) < truePriceTokenA;

        uint256 invariant = reserveA.mul(reserveB);

        uint256 leftSide = Babylonian.sqrt(
            FullMath.mulDiv(
                invariant.mul(1000),
                aToB ? truePriceTokenA : truePriceTokenB,
                (aToB ? truePriceTokenB : truePriceTokenA).mul(997)
            )
        );
        uint256 rightSide = (aToB ? reserveA.mul(1000) : reserveB.mul(1000)) / 997;

        if (leftSide < rightSide) return (false, 0);

        // compute the amount that must be sent to move the price to the profit-maximizing price
        amountIn = leftSide.sub(rightSide);
    }

    // gets the reserves after an arbitrage moves the price to the profit-maximizing ratio given an externally observed true price
    function getReservesAfterArbitrage(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB
    ) view internal returns (uint256 reserveA, uint256 reserveB) {
        // first get reserves before the swap
        (reserveA, reserveB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);

        require(reserveA > 0 && reserveB > 0, 'UniswapV2ArbitrageLibrary: ZERO_PAIR_RESERVES');

        // then compute how much to swap to arb to the true price
        (bool aToB, uint256 amountIn) = computeProfitMaximizingTrade(truePriceTokenA, truePriceTokenB, reserveA, reserveB);

        if (amountIn == 0) {
            return (reserveA, reserveB);
        }

        // now affect the trade to the reserves
        if (aToB) {
            uint amountOut = UniswapV2Library.getAmountOut(amountIn, reserveA, reserveB);
            reserveA += amountIn;
            reserveB -= amountOut;
        } else {
            uint amountOut = UniswapV2Library.getAmountOut(amountIn, reserveB, reserveA);
            reserveB += amountIn;
            reserveA -= amountOut;
        }
    }

    // computes liquidity value given all the parameters of the pair
    function computeLiquidityValue(
        uint256 reservesA,
        uint256 reservesB,
        uint256 totalSupply,
        uint256 liquidityAmount,
        bool feeOn,
        uint kLast
    ) internal pure returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        if (feeOn && kLast > 0) {
            uint rootK = Babylonian.sqrt(reservesA.mul(reservesB));
            uint rootKLast = Babylonian.sqrt(kLast);
            if (rootK > rootKLast) {
                uint numerator1 = totalSupply;
                uint numerator2 = rootK.sub(rootKLast);
                uint denominator = rootK.mul(5).add(rootKLast);
                uint feeLiquidity = FullMath.mulDiv(numerator1, numerator2, denominator);
                totalSupply = totalSupply.add(feeLiquidity);
            }
        }
        return (reservesA.mul(liquidityAmount) / totalSupply, reservesB.mul(liquidityAmount) / totalSupply);
    }

    // get all current parameters from the pair and compute value of a liquidity amount
    // **note this is subject to manipulation, e.g. sandwich attacks**. prefer passing a manipulation resistant price to
    // #getLiquidityValueAfterArbitrageToPrice
    function getLiquidityValue(
        address factory,
        address tokenA,
        address tokenB,
        uint256 liquidityAmount
    ) internal view returns (uint256 tokenAAmount, uint256 tokenBAmount) {
        (uint256 reservesA, uint256 reservesB) = UniswapV2Library.getReserves(factory, tokenA, tokenB);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        bool feeOn = IUniswapV2Factory(factory).feeTo() != address(0);
        uint kLast = feeOn ? pair.kLast() : 0;
        uint totalSupply = pair.totalSupply();
        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }

    // given two tokens, tokenA and tokenB, and their "true price", i.e. the observed ratio of value of token A to token B,
    // and a liquidity amount, returns the value of the liquidity in terms of tokenA and tokenB
    function getLiquidityValueAfterArbitrageToPrice(
        address factory,
        address tokenA,
        address tokenB,
        uint256 truePriceTokenA,
        uint256 truePriceTokenB,
        uint256 liquidityAmount
    ) internal view returns (
        uint256 tokenAAmount,
        uint256 tokenBAmount
    ) {
        bool feeOn = IUniswapV2Factory(factory).feeTo() != address(0);
        IUniswapV2Pair pair = IUniswapV2Pair(UniswapV2Library.pairFor(factory, tokenA, tokenB));
        uint kLast = feeOn ? pair.kLast() : 0;
        uint totalSupply = pair.totalSupply();

        // this also checks that totalSupply > 0
        require(totalSupply >= liquidityAmount && liquidityAmount > 0, 'ComputeLiquidityValue: LIQUIDITY_AMOUNT');

        (uint reservesA, uint reservesB) = getReservesAfterArbitrage(factory, tokenA, tokenB, truePriceTokenA, truePriceTokenB);

        return computeLiquidityValue(reservesA, reservesB, totalSupply, liquidityAmount, feeOn, kLast);
    }
}

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return _functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }
    // solhint-disable-previous-line no-empty-blocks

    function _msgSender() internal view returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP. Does not include
 * the optional functions; to access them see {ERC20Detailed}.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev See {ERC20-_mint}.
     *
     * Requirements:
     *
     * - the caller must is owner.
     */
    function mint(address account, uint256 amount) external returns (bool);

    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) external;

    /**
     * @dev See {ERC20-_burnFrom}.
     */
    function burnFrom(address account, uint256 amount) external;

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Treasury is Ownable {
    using SafeMath for uint256;

    // used contracts
    IERC20 internal elp;
    IERC20 internal elc;
    IERC20 internal rElp;
    IERC20 internal usdt;

    // swap router
    IUniswapV2Router02 internal swapRouter;
    
    // swap, for ELC/USDT pair
    IUniswapV2Pair internal elcSwap;
    
    // swap, for ELP/USDT pair
    IUniswapV2Pair internal elpSwap;
     
    // for elp price, decimal is 18
    AggregatorV3Interface internal elpOracle;

    // for elc price, decimal is 18
    AggregatorV3Interface internal elcOracle;

    // global variables
    //  reserve elp
    uint256 private  elpReserveAmount = 0;
    
    //  risk reserve elp
    uint256 private  elpRiskReserve = 0;
     
    //  risk reserve elc
    uint256 private  elcRiskReserve = 0;
   
    // ELCaim price, decimal 
    uint256 private elcAim = 1 * 1e18; 
    
    // Anti-Inflation Factor 0.00005
    uint256 private k = 5; 
   
    address[] private   userArr;
       
    // elcaim renew blockno
    uint256 private RewardRateBeginBlock = 0;
    uint256 private elcaimLastBlock = 0;
  
    // test
    uint256 private durationBlock = 100;
    uint256 private adjustGap = 28;
    uint256 private voteDuration = 20;
    uint256 private voteBaserelpAmount = 1;
    // test 
    
    //uint256 private durationBlock = 20000;
    //uint256 private adjustGap = 28800;
    //uint256 private voteDuration = 201600;
    //uint256 private voteBaserelpAmount = 100;
    // ELP block revenue rate
    uint256 ELPRewardTotal = (2000000 * 1e18);
    uint256 ELPReward = 0;
    uint256 ELPRewardFirstDay = (20000 * 1e18);

    uint256 ELPRewardRatePerBlock =  ELPRewardFirstDay.div(adjustGap);
     
    uint256  public elpPrice = 0;
    uint256  public elcPrice = 0;
     
    // relp amount maparray that user put in pool
    mapping (address => uint256) public rElpAmountArray;
   
    // uRelp put in pool's block number 
    mapping (address => uint256) public rElpBgBlockArray;
   
    // uRelp put in pool's coin*day 
    mapping (address => uint256) public rElpBlockCoinDayArray;

    // elc amount maparray that user put in pool
    mapping (address => uint256) public elcAmountArray;
   
    // total rELP  in bankPool
    uint256 public rElpPoolTotal = 0;
    
    // system accumulative reward per relp hold-time
    uint256 public rewardElpPerCoinStored = 0;    
   
    // last relp change time 
    uint256 public relpLastUpdateTime = 0;
    
    mapping(address => uint256) public elpRewards;
    
    mapping(address => uint256) public elpRewardPerCoinPaid;
   
    // last change status block
    uint256 public lastExpandTime = 0;
    
    // last change status block
    uint256 public lastContractTime = 0;
   
    // 1 day blocks. expand or contract can raise one time in one day.
  
    mapping (address => uint256) public elcRewardPerCoinDayPaid;

    // voting parameters
    uint256 public against = 0;
    uint256 public approve = 0;
    uint256 public turnout = 0;
    uint256 public electorate = 0;
    uint256 public bgProposalBlock = 0;
  
    uint256[] private proposalK; 
    address[] private proposalSender;
   
    address[] private againstSender;
    address[] private approveSender;
  
    event AddELP (address user,uint256 elp_amount,uint256 relp_amount,uint256 elc_amount);

    event WithdrawELP(address user, uint256 relp_amount,uint256 elc_amount,uint256 elp_amount);

    event ExpandCycle (uint256 blockno,uint256 start_price,uint256 elc_amount);

    event ContractCycle (uint256 blockno,uint256 start_price);

    event ChangeK (uint256 blockno,uint256 k);
    
    event AddRiskELP(address user,uint256 elpAmount);

    constructor(address elp_contract, 
                address elc_contract,
                address relp_contract) public {
                
        elp = IERC20(elp_contract);
        elc = IERC20(elc_contract);
        rElp = IERC20(relp_contract);
        
        RewardRateBeginBlock = block.number;    
        elcaimLastBlock = block.number;
    }

    function setOracle(address oracle_contract1, address oracle_contract2) public onlyOwner {
        elpOracle = AggregatorV3Interface(oracle_contract1);
        elcOracle = AggregatorV3Interface(oracle_contract2);
    }

    function setSwap(address elc_usdt_pair, address elp_usdt_pair, address router, address usdt_token) public onlyOwner {
        swapRouter = IUniswapV2Router02(router);
        elcSwap = IUniswapV2Pair(elc_usdt_pair);
        elpSwap = IUniswapV2Pair(elp_usdt_pair);
        usdt = IERC20(usdt_token);
    }

    function chargeAddrSaved()  private view returns (bool)
    {
         for(uint i = 0;i < userArr.length; i++)
        {
            if(userArr[i] ==  msg.sender)
            {
                return true;
            }
        }
        return false;
    }
    
    function deleteAddr(address account) private  returns (bool)
    {
        for(uint i = 0;i < userArr.length; i++)
        {
            if(userArr[i] ==  account)
            {
                userArr[i] = userArr[userArr.length - 1];
                delete userArr[userArr.length - 1];
         
                return true;
            }
        }
        return false;
    }
    
    // add ELP liquidity，returns rELP amount and ELC amount
    function addRiskReserveElp(uint256 elpAmount) public onlyOwner returns(bool) 
    {
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(!ret)
        {
          return false;
        }
      
        elpRiskReserve += elpAmount;
     
        emit AddRiskELP(msg.sender, elpAmount);
        return true;
    }

     // add ELP liquidity，returns rELP amount and ELC amount
    function addReserveElp(uint256 elpAmount) internal  returns(bool) 
    {
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(!ret)
        {
          return false;
        }  
       
        elpReserveAmount = elpReserveAmount + elpAmount;
     
        return true;
    }
    
    // add ELP liquidity，returns rELP amount and ELC amount
    function addRewardsElp(uint256 elpAmount) public onlyOwner  returns(bool) 
    {
        require(elpAmount > 0, "elp amount must > 0");
        require(ELPReward + elpAmount < ELPRewardTotal, "reward elp amount must < totalreward");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(!ret)
        {
          return false;
        }  
       
        ELPReward = ELPReward + elpAmount;
     
        return true;
    }
  
    // add ELP liquidity，returns rELP amount and ELC amount
    function addElp(uint256 elpAmount) public updateRewardELP returns(uint256 relpAmount, uint256 elcAmount) 
    {
        require(elpAmount > 0, "elp amount must > 0");

        bool ret = addReserveElp(elpAmount);
        if(!ret)
        {
          return (0,0);
        }
        
        uint256 relp_amount = 0;
        uint256 elc_amount = 0;
        (relp_amount, elc_amount) = computeRelpElcbyAddELP(elpAmount);
        
        if (elc_amount > 0) {
            elc.mint(address(this), elc_amount);
            elcAmountArray[msg.sender] += elc_amount;
        }
    
        if (relp_amount > 0) {
            rElp.mint(address(this), relp_amount);
            
            rElpAmountArray[msg.sender] += relp_amount;
            rElpPoolTotal += relp_amount;
          
            if(rElpBgBlockArray[msg.sender] > 0)
            {
               rElpBlockCoinDayArray[msg.sender] += rElpAmountArray[msg.sender].mul(block.number.sub(rElpBgBlockArray[msg.sender]) );
            }else{
               rElpBlockCoinDayArray[msg.sender] = 0;
            }
            rElpBgBlockArray[msg.sender] = block.number;
        } 
       
        bool isSaved = chargeAddrSaved();
        if(!isSaved)
        {
             userArr.push(msg.sender);
        }
       
        emit AddELP(msg.sender, elpAmount, relp_amount, elc_amount);
        return (relp_amount, elc_amount);
    }

    // withdraw elp，
    function withdrawElp(uint256 elpAmount) public updateRewardELP lrLess90 returns(bool) {
        require(elpAmount > 0, 'WithdrawElp: elpAmount must > 0 ');
        require(ELPReward > elpRewards[msg.sender],"WithdrawElp: ELPReward must > elpRewards[msg.sender]");
         bool ret;
        if(elpAmount < elpRewards[msg.sender])
        {
              ret = elp.transfer(msg.sender, elpAmount);
             elpRewards[msg.sender] -= elpAmount;
           
             return ret;
        }
       
        uint256 tmpElpNeed = elpAmount - elpRewards[msg.sender];
        uint256 elcNeed;
        uint256 relpNeed;
        (elcNeed,relpNeed) = computeRelpElcbyAddELP(tmpElpNeed);
      
       if(elcAmountArray[msg.sender]  < elcNeed  || rElpAmountArray[msg.sender]  < relpNeed)
       {
           return false;
       }
    
       elcAmountArray[msg.sender]  = elcAmountArray[msg.sender] - elcNeed;
        
       elc.burn(elcNeed);
       
       rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender]  - relpNeed;
        
       rElpPoolTotal -= relpNeed;
     
       elpRewards[msg.sender] = 0; 
       
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == 0)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
        }else{
             rElpBlockCoinDayArray[msg.sender] += (rElpAmountArray[msg.sender].sub(relpNeed)).mul(block.number.sub(rElpBgBlockArray[msg.sender]));
        }
        rElpBgBlockArray[msg.sender] = block.number;
     
        rElp.burn(relpNeed);

        ret = elp.transfer(msg.sender, elpAmount);
        if(ret){
           elpReserveAmount = elpReserveAmount - tmpElpNeed; 
        }
        return ret;
    }

    function addElc(uint256 elcAmount) public  returns(bool){
        bool ret = elc.transferFrom( msg.sender,address(this), elcAmount);
        if(ret)
        {
             elcAmountArray[msg.sender] += elcAmount;
        }
        return ret;
    }
    
    function withdrawElc(uint256 elcAmount) public  returns(bool){
        require(elcAmount <= elcAmountArray[msg.sender],"withdrawElc:withdraw amount must less than elcAmountArray hold!");
      
        bool ret = elc.transfer(msg.sender, elcAmount);
        elcAmountArray[msg.sender] -= elcAmount;   
        return ret;
    }

    function getElcAmount() public view returns (uint256){
        return elcAmountArray[msg.sender];
    }
   
    // user withdraw rELP and send it to user address
    function withdrawRELP(uint256 relpAmount)  public updateRewardELP{
        
        require(relpAmount <= rElpAmountArray[msg.sender],"withdrawRELP:withdraw amount must less than rElpAmountArray hold!");
       
        //getReward();
        
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == relpAmount)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
        }else{
             rElpBlockCoinDayArray[msg.sender] += (rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender]));
        }
        rElpBgBlockArray[msg.sender] = block.number;
        
        rElpAmountArray[msg.sender] -= relpAmount;
        rElpPoolTotal -= relpAmount;
        rElp.transfer(msg.sender, relpAmount);
    }

    // user add rELP to pool, liquidity miner
    function addRELP(uint256 relpAmount) public updateRewardELP{
        
      //  getReward();
        rElp.transferFrom(msg.sender, address(this), relpAmount);
        rElpBlockCoinDayArray[msg.sender] += (rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender]));
        rElpBgBlockArray[msg.sender] = block.number;
     
        rElpPoolTotal += relpAmount;
        rElpAmountArray[msg.sender] += relpAmount;
        
        bool isSaved = chargeAddrSaved();
        if(!isSaved)
        {
             userArr.push(msg.sender);
        }
    }

    function getRelpAmount() public view returns (uint256){
       
       return rElpAmountArray[msg.sender];
    }

    // expand cycle. raise ELC, swap ELC to ELP
    function expansion() public 
    updateElcAim 
    lrLess70  
    elcPriceOverUplimit 
    expandInOneDayAg 
    returns(uint256) {
       
        uint256 elcSwapPrice = getElcPrice();
      
        // amount of expand elc
        uint256 expandAmount  = elcSwapPrice.sub(elcAim).mul(elc.totalSupply()).div(elcAim);
        uint256 elpAmount;
        
        // call swap path
        address[] memory path1 = new address[](2);
        path1[0] = address(elcSwap);
        path1[1] = address(elpSwap);

        uint[] memory amounts = new uint[](2);
 
        if( elcRiskReserve >= expandAmount) {
            // swap to elp
            amounts = swapRouter.swapExactTokensForTokens(expandAmount, 1E18, path1, address(this), 1);
            elpAmount = amounts[1];
            elcRiskReserve -= expandAmount;
            elpRiskReserve += elpAmount;
            
        } else {
            amounts = swapRouter.swapExactTokensForTokens(elcRiskReserve, 1E18, path1, address(this), 1);
            elpAmount = amounts[1];
            elpRiskReserve += elpAmount;
            
            uint256 mintAmount = expandAmount.sub(elcRiskReserve);
            elcRiskReserve = 0;
            
            elc.mint(address(this), mintAmount);
          
            amounts = swapRouter.swapExactTokensForTokens(mintAmount.mul(5).div(100), 1E18, path1, address(this), 1);
            elpAmount = amounts[1];
            elpRiskReserve += elpAmount;

            uint256  expandElcforRelp = mintAmount.mul(95).div(100);
            uint256 rElpCoinDayTotal = 0;
            for(uint i = 0;i < userArr.length; i++)
            {
               rElpBlockCoinDayArray[userArr[i]] += (rElpAmountArray[userArr[i]]).mul(block.number - rElpBgBlockArray[userArr[i]]);
               rElpCoinDayTotal += rElpBlockCoinDayArray[userArr[i]];
            }
            
            if(expandElcforRelp > 0 && rElpCoinDayTotal > 0)
            {
               uint256 elcPerCoinDay = expandElcforRelp.div(rElpCoinDayTotal);
               for(uint i = 0;i < userArr.length; i++)
               {
                  elcAmountArray[userArr[i]] += elcPerCoinDay.mul(rElpBlockCoinDayArray[userArr[i]]);
                  rElpBgBlockArray[userArr[i]] = block.number;
                  rElpBlockCoinDayArray[userArr[i]]  = 0;
               }
            }
        }    
        lastExpandTime = block.number;
        emit ExpandCycle(block.number, elcPrice, expandAmount);
        return expandAmount;
    }

    // contract cycle. swap ELP to ELC
    function contraction() public  
    elcPriceOverDownlimit 
    contractInOneDayAg 
    updateElcAim 
    returns(uint256) {
        uint256 elcAmount;
        // query amount from swap, how many elp to raise elc to 98% elcaim
        uint256 elpNeed;
        elpNeed = computeElpNeed();

        // call swap path
        address[] memory path2 = new address[](2);
        path2[0] = address(elpSwap);
        path2[1] = address(elcSwap);
        uint[] memory amounts = new uint[](2);

        if (elpNeed <= elpRiskReserve) {
            amounts = swapRouter.swapExactTokensForTokens(elpNeed, 1E18, path2, address(this), 1);
            elcAmount = amounts[1];
            elpRiskReserve -= elpNeed;
            elcRiskReserve += elcAmount;
        } else {
            uint256 elp2percent = elpReserveAmount.mul(2).div(100);
            if(elpNeed < elpRiskReserve.add(elp2percent)) {
                amounts = swapRouter.swapExactTokensForTokens(elpNeed, 1E18, path2, address(this), 1);
                elcAmount = amounts[1];
                elpReserveAmount = elpReserveAmount.add(elpRiskReserve).sub(elpNeed);
                elpRiskReserve = 0;
                elcRiskReserve += elcAmount;
            } else {
                elpNeed = elpRiskReserve.add(elp2percent);
                amounts = swapRouter.swapExactTokensForTokens(elpNeed, 1E18, path2, address(this), 1);
                elcAmount = amounts[1];
                elcRiskReserve += elcAmount;
                elpRiskReserve = 0;
                elpReserveAmount -= elp2percent;
            }
        }
    
       lastContractTime = block.number;
       emit ContractCycle(block.number, elpNeed);
       return elpNeed; 
    }

    // query：
    // compute the ELP amount get rELP amount and ELC amount
    function computeRelpElcbyAddELP(uint256  elp_amount) public view returns(uint256 relpAmount, uint256 elcAmount) {
        
        uint256  elp_price = getElpPrice();
        uint256  elc_price = getElcPrice();
        uint256  relp_amount;
        uint256  elc_amount;
        uint256  lr = liabilityRatio();
       
        if (lr <= 30) {
             uint256   relp_price = computeRelpPrice();
             if(relp_price > 0)
             {
                 uint256  temp = elp_amount.mul(elp_price).mul(100 - lr );
          
                 relp_amount = temp.div(relp_price).div(100);
             }
             
             if(elc_price > 0)
             {
                 elc_amount  = elp_amount.mul(elp_price).mul(lr);
                 elc_amount  = elc_amount.div(elc_price).div(100);
             }
        } else if (lr <= 90){
              uint256   relp_price = computeRelpPrice();
            if(relp_price > 0)
            {
                relp_amount = elp_amount.mul(elp_price).div(relp_price);
            }
            elc_amount  = 0; 
        } else if (lr > 90){
              uint256  relp_price_90 = computeRelpPrice90();
            if(relp_price_90 > 0)
            {
                relp_amount = elp_amount.mul(elp_price).div(relp_price_90);
            }
            elc_amount  = 0; 
        }
        return (relp_amount, elc_amount);
    }

    // query:
    // estimate ELC value: value per ELC in swap
    function querySwapElcPrice() public view returns(uint256) {
        uint256 usdtPerElc;
        uint256 a0;
        uint256 a1;
        uint256 t0;
        (a0, a1, t0) = elcSwap.getReserves();

        if(elc < usdt) {
            usdtPerElc = UniswapV2Library.getAmountOut(1E18, a0, a1);
        } else {
            usdtPerElc = UniswapV2Library.getAmountOut(1E18, a1, a0);
        }
        return usdtPerElc;
    }

   // query:
    // estimate ELC value: value per ELC in swap
    function querySwapElpPrice() public view returns(uint256) {
        uint256 usdtPerElp;
        uint256 a0;
        uint256 a1;
        uint256 t0;
        (a0, a1, t0) = elpSwap.getReserves();

        if(elp < usdt) {
            usdtPerElp = UniswapV2Library.getAmountOut(1E18, a0, a1);
        } else {
            usdtPerElp = UniswapV2Library.getAmountOut(1E18, a1, a0);
        }
        return usdtPerElp;
    }

    // query:
    // compute elp_need by swap to swap
    function computeElpNeed() public view returns(uint256) {
        uint256 usdt_need;
        uint32 timeStamp;
      
        bool usdtToELC;
       
        // two step work to compute
        uint256 reserveUSDT;
        uint256 reserveELC;
       
        (reserveUSDT, reserveELC, timeStamp) = elcSwap.getReserves();
       
        (usdtToELC, usdt_need) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                1E18, (elcAim * 98 * 1E18),
                reserveUSDT, reserveELC
            );
       
        require(usdt_need > 0);
        
        uint256 reserveELP;
        uint256 reserveUSDT2;
        
        (reserveELP, reserveUSDT2, timeStamp) = elpSwap.getReserves();
        
        require(usdt_need < reserveUSDT2);
        
        uint256 elp_need;
        
        if(elp < usdt) {
            elp_need = UniswapV2Library.getAmountOut(usdt_need, reserveUSDT2, reserveELP);
        } else {
            elp_need = UniswapV2Library.getAmountOut(usdt_need, reserveELP, reserveUSDT2);
        }
        return elp_need;
    }

    // query:
    // get reserve
    function getElpReserve() public view returns(uint256) {
        return elpReserveAmount;
    }

    // query:
    // get risk_reserve
    function getElpRiskReserve() public view returns(uint256) {
        return elpRiskReserve;
    }

    // query:
    // get risk_reserve ELC
    function getElcRiskReserve() public view returns(uint256) {
        return elcRiskReserve;
    }

    // query:
    // get K factor
    function getK() public view returns(uint256) {
        return k;
    }

    // compute rELP price
    function computeRelpPrice() public view returns(uint256) {
       
        uint256 elp_price = getElpPrice();
        uint256 elc_price = getElcPrice();
        uint256 relp_total = rElp.totalSupply();
        uint256 elc_total  = elc.totalSupply();
        
        if (relp_total > 0) {
                if(elpReserveAmount > 0 && (elpReserveAmount.mul(elp_price) > elc_total.mul(elc_price)))
                {
                    return ((elpReserveAmount.mul(elp_price)).sub(elc_total.mul(elc_price)).div(relp_total));
                }else{
                      return 1E18; 
                }
        } else {
                // set to proper number when deployed, never set zero
                 return 1E18; 
            }
    }
    
    // lr = 90%  prelp
    function computeRelpPrice90() public view returns(uint256){
        uint256 elp_price = getElpPrice();
        uint256 relp_total = rElp.totalSupply();
      
        if (relp_total > 0) {
             if(elpReserveAmount > 0  && relp_total > 0)
             {
                 return ((elpReserveAmount.mul(elp_price)).mul(90).div(relp_total)).div(100);
             }
             else
             {
                 return 1E18; 
             }
        } else {
                // set to proper number when deployed, never set zero
                 return 1E18; 
        }
    }
    
    function liabilityRatio() public view returns(uint256) {
        // not only initial, anytime reserve down to zero should protect.
        if (elpReserveAmount == 0) {
            return 20;
        }

        uint256 lr;
        uint256 elp_price = getElpPrice();
        uint256 elc_price = getElcPrice();
        uint256 elc_total = elc.totalSupply();
        if(elp_price > 0 && elpReserveAmount > 0)
        {
            lr =  elc_total.mul( elc_price).mul(100 ).div(elpReserveAmount.mul(elp_price));
        }
        
        if (lr >= 100) {
            // up bound is 100
            return 100;
        }

        if (lr == 0) {
            return 1;
        }
        return lr;
    }

    // update elcaim price by K Factor.
    modifier updateElcAim(){
       //  require((block.number).sub(elcaimLastBlock) > durationBlock,"aim price has updated in the same duration " );
       votingResult();  
       if((block.number).sub(elcaimLastBlock) >= durationBlock)
       {
           uint256 span = (block.number).sub(elcaimLastBlock).div(durationBlock);
           for(uint256 i = 0; i < span; i++) {
              elcAim = elcAim.mul(100000 +k).div(100000);
           }
           elcaimLastBlock = block.number;
       }
      _;
    }

    // Determine if elc price exceeds1.02
    modifier elcPriceOverUplimit(){
        uint256 elc_price = getElcPrice();
        uint256 elc_up_limit = elcAim.mul(102).div(100);
        require(elc_price > elc_up_limit,"elcPrice must great than upLimits");
     _;
    }
    
    // Determine if elc price overdown 0.98  
    modifier elcPriceOverDownlimit(){
        uint256 elc_price = getElcPrice();
        uint256 elc_down_limit = elcAim.mul(98).div(100);
        require(elc_price < elc_down_limit,"elcPrice must small than downLimits");
     _;
    }
 
    // judgment of Expansion
    modifier expandInOneDayAg(){
       require(block.number > (lastExpandTime.add(adjustGap)),"expansion: can expand once in one day");
     _;        
    }   
    
    // Judgment of systole
    modifier contractInOneDayAg(){
       require(block.number > (lastContractTime.add(adjustGap)),"expansion: can expand once in one day");
     _;        
    }   
    
    // caculate the lr make sure is less than 90.
    modifier lrLess90(){
       require(liabilityRatio() < 90, 'lrOver90: lr must < 90 ');
        _;
    }
    
    // caculate the lr make sure is less than 70.
    modifier lrLess70(){
       require(liabilityRatio() < 70, 'lrOver90: lr must < 90 ');
       _; 
    }   
    
    // 每token奖励
    function getElpRewardPerCoin() public view returns (uint256) {
        uint256 span = (block.number - RewardRateBeginBlock).div(28800);
        uint256 RatePerBlock = 0;
        if(span > 0)
        {
            for(uint256 i = 0; i < span; i++)
            {
               RatePerBlock = ELPRewardRatePerBlock.mul(99).div(100);
            }
        }
        
        if (rElpPoolTotal == 0) 
        {
            return rewardElpPerCoinStored;
        }
       
        return         
            rewardElpPerCoinStored.add(
                    ((block.number)
                    .sub(relpLastUpdateTime))
                    .mul(RatePerBlock)
                    .mul(1e18)
                    .div(rElpPoolTotal)
       );
    }
    
    modifier updateRewardELP() {
        // if elp reward amount is so few，forbiden reward 
        if(ELPReward >= 1)
        {
            uint256 span = (block.number - RewardRateBeginBlock).div(adjustGap);
            if(span > 0)
            {
                for(uint256 i = 0; i < span; i++)
                {
                   ELPRewardRatePerBlock = ELPRewardRatePerBlock.mul(99).div(100);
                }
                RewardRateBeginBlock = block.number;
            }
            rewardElpPerCoinStored = getElpRewardPerCoin();
            relpLastUpdateTime = block.number;
            elpRewards[msg.sender] = rewardELP(); 
            ELPReward -= elpRewards[msg.sender];
            elpRewardPerCoinPaid[msg.sender] = rewardElpPerCoinStored;
        }
        _;
    }
 
    function rewardELP() public view returns (uint256) {
        uint256 tmp = rElpAmountArray[msg.sender];
        return tmp
                .mul(getElpRewardPerCoin().sub(elpRewardPerCoinPaid[msg.sender]))
                .div(1e18)
                .add(elpRewards[msg.sender]);
    }

    // get elp price from chainlink oracle
    function getElpPrice() public view returns (uint256) {
       return elpPrice;
    /* 
      uint80 roundId;
      int256 price;
      uint256 startedAt;
      uint256 updatedAt;
      uint80 answeredInRound;
      
      (roundId,price,startedAt,updatedAt,answeredInRound) = elpOracle.latestRoundData();
     
     if( price > 0)
        return uint256(price);
      else
        return 0;
    */    
    }
    
    // get elc price from chainlink oracle
    function getElcPrice() public view returns (uint) {
       return elcPrice;
    /*
      uint80 roundId;
      int256 price;
      uint256 startedAt;
      uint256 updatedAt;
      uint80 answeredInRound;

      (roundId,price,startedAt,updatedAt,answeredInRound) = elcOracle.latestRoundData();
     
     if( price > 0)
        return uint256(price);
      else
        return 0;
    */    
    }

    //----------------------------------------k投票治理-----------------------------//      
    function proposal(uint256 detaK) public returns (bool) {
       require(detaK > 0,"proposal:detaK must > 0");
       if(rElpAmountArray[msg.sender] < voteBaserelpAmount)
        {
            return false;
        }
        
       if( block.number - bgProposalBlock > voteDuration)
        {
            return false;
        }
        
        for(uint256 i = 0; i < proposalSender.length; i++)
        {
            if(proposalSender[i] == msg.sender)
             {
                 return false;
             }
        }
         
        proposalK.push(detaK); 
        proposalSender.push(msg.sender);
        
        for(uint256 i = 0; i < proposalK.length; i++)
        {
             if(proposalK[i] < detaK)
             {
                   for(uint256 j = proposalK.length -1; j >= i ; j--)
                   {
                       proposalK[j] =  proposalK[j-1];
                       proposalSender[j] =  proposalSender[j-1];
                   }
                   proposalK[i] =  detaK;
                   proposalSender[i] =  msg.sender;
                   break;
             }
        }
        
        turnout += rElpAmountArray[msg.sender];
        approve += rElpAmountArray[msg.sender];
       
        if(bgProposalBlock == 0)
        {
            bgProposalBlock = block.number;
        }
        
        approveSender.push(msg.sender);
        return true;
    }
  
    function getProposalTaget() public view returns(uint256){
       
        if(proposalK.length > 0)
        {
            return proposalK[0];
        }
        return 0;
    }
 
    function approveVote() public returns (bool){
        if(rElpAmountArray[msg.sender] < voteBaserelpAmount)
        {
            return false;
        }
        
        if(block.number - bgProposalBlock  < voteDuration  &&  block.number - bgProposalBlock > voteDuration.mul(2))
        {
           return false;
        }
        
        for(uint256 i = 0; i < approveSender.length; i++)
        {
             if(approveSender[i]==msg.sender)
                return false;
        }
        
        turnout += rElpAmountArray[msg.sender];
        approve += rElpAmountArray[msg.sender];
        for(uint256 i = 0; i < approveSender.length; i++)
        {
            if(approveSender[i]== address(0))
              {
                 approveSender[i] = msg.sender;
                 return true;
              }
        }
        approveSender.push(msg.sender);
        return true;
    }
    
    function withdrawProposal() public returns (bool) {
       // require(block.number - bgProposalBlock  < 201600); 
        if(block.number - bgProposalBlock  > voteDuration)
        {
            return false;
        }
        
        bool isProposalSender = false;
        for(uint256 i = 0; i < proposalSender.length; i++ )
        {
            if(proposalSender[i] == msg.sender)
            {
                if(i == 0)
                {
                  bgProposalBlock = 0;
                }
                
                isProposalSender = true;
                 for(uint256 j = i; j < proposalSender.length - 1; i++ )
                 {
                    proposalSender[j] = proposalSender[j+1]; 
                     proposalK[j] =  proposalK[j+1];
                 }
                 proposalSender[proposalSender.length - 1] = address(0);
                 proposalK[proposalSender.length - 1] = 0;
                 break;
            }
        }
       
        if(isProposalSender == false)
          return false;
          
        if(proposalK[0] > 0){
            if(bgProposalBlock == 0)
             {
                    bgProposalBlock = block.number;
             }
        }
        return true;
    }
    
    function againstVote() public returns (bool){
      //   require( rElpAmountArray[msg.sender]> 100);
      //   require( block.number - bgProposalBlock  > 201600  && block.number - bgProposalBlock < 403200 );
         if(rElpAmountArray[msg.sender] < voteBaserelpAmount)
         {
             return false;
         }
         
         if(block.number - bgProposalBlock  < voteDuration || block.number - bgProposalBlock > voteDuration.mul(2))
         {
             return false;
         }
         
         for(uint256 i = 0; i < againstSender.length; i++)
         {
            if(againstSender[i]==msg.sender)
                return false;
         }
         
         turnout += rElpAmountArray[msg.sender];
         against += rElpAmountArray[msg.sender];
         
         for(uint256 i = 0; i < againstSender.length; i++)
         {
            if(againstSender[i] == address(0))
            {
                againstSender[i] = msg.sender;
                return true;
            }
         }
         againstSender.push(msg.sender);
         return true;
    }
  
    function votingResult() public returns (bool){
    //   require( bgProposalBlock > 0 &&  block.number - bgProposalBlock > 403200,"votingResult: must in a round of voting");
      if(bgProposalBlock > 0 &&  block.number - bgProposalBlock > voteDuration.mul(2))
      {
          return false;
      }
      
       bool votingRet = false;
       electorate = rElp.totalSupply();  
       if(turnout == 0)
       {
           turnout = 1;
       }
       uint256 agreeVotes = against.mul(against).div(turnout) ;
       uint256 disagreeVotes =  approve.mul(approve).div(electorate) ;
      
       if(agreeVotes > disagreeVotes )
       {
           k =  proposalK[0]; 
           votingRet = true;
       }
       
       bgProposalBlock = 0;
       for(uint256 j = 0; j < proposalSender.length - 1 ; j++ )
       {
            proposalSender[j] = proposalSender[j+1]; 
            proposalK[j] =  proposalK[j+1];
       }
       
       proposalSender[proposalSender.length - 1] = address(0);
       proposalK[proposalSender.length - 1] = 0;
       against = 0;
       approve = 0;
       turnout = 0;
       electorate = 0;
       if(proposalK[0] > 0 && bgProposalBlock == 0){
          bgProposalBlock = block.number;
       }
        
       for(uint256 i = 0; i < againstSender.length; i++ )
       {
            againstSender[i] = address(0);
       }
        
       for(uint256 i = 0; i < approveSender.length; i++ )
       {
            approveSender[i] = address(0);
       }     
       return votingRet;
    }
    //-----------------------测试用-------------------------------------------------//
  
    function setElpPrice(uint256 price) public {
       elpPrice = price;
    }
    
    function setElcPrice(uint256 price) public {
      elcPrice = price;
    }
}
