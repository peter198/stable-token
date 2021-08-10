/**
2021-05-17
author: Leopard
*/

pragma solidity >=0.6.0 <0.8.0;
/**
 * @title pool 1.0
 */
 
 import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
 import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
 import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
 
 import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
 import "https://github.com/Uniswap/uniswap-lib/blob/master/contracts/libraries/Babylonian.sol";
 import "https://github.com/Uniswap/uniswap-lib/blob/master/contracts/libraries/FullMath.sol";

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
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
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
 * @dev Enhance Interface of the ERC20.
 */
interface EIERC20 is IERC20 {
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
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    //constructor () internal {
    constructor () public {
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


contract pool  is Ownable {
    using SafeMath for uint256;

    // used contracts

    EIERC20 internal elp;
    EIERC20 internal elc;
    EIERC20 internal relp;

    IERC20 internal usdt;

    // swap Factory
    //IUniswapV2Factory swapFactory;
    IUniswapV2Router02 swapRouter;
    // swap, for ELC/USDT pair
    IUniswapV2Pair internal elcSwap;
    // swap, for ELP/USDT pair
    IUniswapV2Pair internal elpSwap;

    // for elp price, decimal is 8
    AggregatorV3Interface  elp_oracle;
    // for elc price, decimal is 8
    AggregatorV3Interface  elc_oracle;

    // global variables
    // reserve elp
    uint256 elp_reserve = 0;
    // reserve elc
    uint256 elc_reserve = 0;
    // risk reserve elp
    uint256 elp_risk_reserve = 0;
    // risk reserve elc
    uint256 elc_risk_reserve = 0;

    // ELCaim price, decimal 8
    uint256 elcaim = 100000000;
    // Anti-Inflation Factor
    uint256 k = 5;
    // elcaim renew blockno
    uint256 elcaim_last_block;

    // relp put in pool
    uint256 relp_in_pool = 0;
   
    // relp hold-time total
    uint256 relp_hc_total = 0;
   
    // system accumulative reward per relp hold-time
    uint256 acc_reward_per_hc = 0;
   
    // last compute blockno
    uint256 last_block;
  
    // system accumulative reward elc per relp hold-time
    uint256 acc_reward_elc_per_hc = 0;
  
    // last compute elc blockno
    uint256 elc_last_block;

    // last expand block
    uint256 last_expand_time = 0;
    // last contract block
    uint256 last_contract_time = 0;
    // 1 day blocks. expand or contract can raise one time in one day.
    uint256 adjust_gap = 28800;

    // relp amount that user put in pool
    mapping (address => uint256) public u_relp;
   
    // last block then compute for the user
    mapping (address => uint256) public u_lastblock;
   
    // relp hold-time amount of user
    mapping (address => uint256) public u_relp_hc;
    
    // last system reward per hold-time
    mapping (address => uint256) public start_sys_per_hc;
    
    // last system elc reward per hold-time
    mapping (address => uint256) public start_sys_elc_per_hc;

    event AddELP (
        address user,
        uint256 elp_amount,
        uint256 relp_amount,
        uint256 elc_amount
    );

    event RemoverELP (
        address user,
        uint256 relp_amount,
        uint256 elc_amount,
        uint256 elp_amount
    );

    event ExpandCycle (
        uint256 blockno,
        uint256 start_price,
        uint256 elc_amount
    );

    event ContractCycle (
        uint256 blockno,
        uint256 start_price
    );

    event ChangeK (
        uint256 blockno,
        uint256 k
    );

    constructor (address elp_contract, address elc_contract, address relp_contract) public {
        elp = EIERC20(elp_contract);
        elc = EIERC20(elc_contract);
        relp = EIERC20(relp_contract);
        last_block =  block.number;
        elcaim_last_block = block.number;
    }

    function set_oracle(address oracle_contract1, address oracle_contract2) public onlyOwner {
        elp_oracle = AggregatorV3Interface(oracle_contract1);
        elc_oracle = AggregatorV3Interface(oracle_contract2);
    }

    function set_swap(address elc_usdt_pair, address elp_usdt_pair, address router, address usdt_token) public onlyOwner {
        swapRouter = IUniswapV2Router02(router);
        elcSwap = IUniswapV2Pair(elc_usdt_pair);
        elpSwap = IUniswapV2Pair(elp_usdt_pair);
        usdt = IERC20(usdt_token);
    }

    // add ELP liquidity，returns rELP amount and ELC amount
    function add_ELP(address elp_contract, uint256 elp_amount) public returns(uint256, uint256) {
        require(elp == IERC20(elp_contract));
        require(elp_amount > 0);

        update_elc_aim();

        assert(elp.transferFrom(msg.sender, address(this), elp_amount));
    
        uint256 relp_amount;
        uint256 elc_amount;
        (relp_amount, elc_amount) = compute_add_ELP(elp_amount);

        if (elc_amount > 0) {
            assert(elc.mint(msg.sender, elc_amount));
        }

        assert(relp.mint(address(this), relp_amount));
        elp_reserve += elp_amount;
        deal_acc_pool();

        // when a user add ELP first time 
        if(u_lastblock[msg.sender] == 0) {
            u_lastblock[msg.sender] = block.number;
            u_relp[msg.sender] = 0;
        }

        u_relp_hc[msg.sender] += u_relp[msg.sender]*(block.number.sub(u_lastblock[msg.sender]));
        u_relp[msg.sender] += relp_amount;
        u_lastblock[msg.sender] = block.number;
        relp_in_pool += relp_amount;
        // last system reward per hold-time
        start_sys_per_hc[msg.sender] = acc_reward_per_hc;
        start_sys_elc_per_hc[msg.sender] = acc_reward_elc_per_hc;

        emit AddELP(msg.sender, elp_amount, relp_amount, elc_amount);
        return (relp_amount, elc_amount);
    }

    // remove liquidity，returns amount of ELP
    function remove_rELP(uint256 relp_amount, uint256 elc_amount) public returns(uint256) {
        require(relp_amount > 0);
        require(elc_amount > 0);

        uint256 elp_price;
        uint256 elc_price;
        uint256 lr;
        uint256 relp_price;
        uint256 elc_need;
        uint256 hc_dec;

        update_elc_aim();
        assert(u_relp[msg.sender] >= relp_amount);

        (elp_price, elc_price) = get_price();
        lr = liability_ratio();
        assert(lr < 90);
    
        relp_price = compute_relp_price();
        elc_need = relp_amount * relp_price * lr / (elc_price * (100-lr));
        assert(elc_need <= elc_amount);

        get_reward();
        uint256 elp_amount = (elc_need * elp_price + relp_amount * relp_price) / elp_price;

        relp.burnFrom(address(this), relp_amount);
        relp_in_pool -= relp_amount;
        // part remove, all remove , can deal too
        hc_dec = u_relp_hc[msg.sender] * relp_amount / u_relp[msg.sender];
        u_relp_hc[msg.sender] -= hc_dec;
        relp_hc_total -= hc_dec;
        u_relp[msg.sender] -= relp_amount;
        // last system reward per hold-time
        start_sys_per_hc[msg.sender] = acc_reward_per_hc;
        start_sys_elc_per_hc[msg.sender] = acc_reward_elc_per_hc;

        elc.burnFrom(msg.sender, elc_amount);
        elp.transferFrom(address(this), msg.sender, elp_amount);
        elp_reserve -= elp_amount;

        emit RemoverELP(msg.sender, relp_amount, elc_amount, elp_amount);
        return elp_amount;
    }

    // user get reward, returns amount of reward
    function get_reward() public returns(uint256) {
        uint256 relp_amount = u_relp[msg.sender];
        uint256 elp_amount = 0;
    
        update_elc_aim();
        assert(relp_amount > 0);
        deal_acc_pool();
        uint256 elp_reward = ((acc_reward_per_hc).sub(start_sys_per_hc[msg.sender]))*relp_amount;
        if (elp_risk_reserve >= elp_reward) {
            elp.transfer(msg.sender, elp_reward);
            elp_risk_reserve -= elp_amount;
        }

        uint256 elc_reward = ((acc_reward_elc_per_hc).sub(start_sys_elc_per_hc[msg.sender]))*relp_amount;
        if (elc_risk_reserve >= elc_reward) {
            elc.transfer(msg.sender, elc_reward);
            elc_risk_reserve -= elc_reward;
        } else {
            // dec the elc_risk_reserve to zero
            elc.transfer(msg.sender, elc_risk_reserve);
            elc_risk_reserve = 0;
        }

        u_lastblock[msg.sender] = block.number;
        //return elp reward
        return elp_reward;
    }

    // expand cycle. raise ELC, swap ELC to ELP
    function expansion_cycle() public returns(uint256) {
        bool in_cycle_flag = false;
        uint256 elp_price;
        uint256 elc_price;
        (elp_price, elc_price) = get_price();

        update_elc_aim();
        uint256 elc_up_limit = elcaim * 102 / 100;
        assert(elc_price > elc_up_limit);

        // 1 day gap, can expand once in one day.
        if(block.number < (last_expand_time + adjust_gap)) {
            in_cycle_flag = true;
        }

        uint256 lr = liability_ratio();

        uint256 usdt_per_elc;
        usdt_per_elc = query_swap_elc_price();
        // if swap price different to oracle price, use swap price
        // if swap price not high, do nothing
        assert(usdt_per_elc > elcaim * 102 * 100000000);

        // 
        uint256 expand_amount = 0;
        if(in_cycle_flag = false) {
            expand_amount = (elc_price - elcaim) * elc.totalSupply() / elcaim;
        }
        uint256 elp_amount;
        // call swap path
        address[] memory path1 = new address[](2);
        path1[0] = address(elcSwap);
        path1[1] = address(elpSwap);

        uint[] memory amounts = new uint[](2);
 
        if( elc_risk_reserve + elc_reserve >= expand_amount) {
            amounts = swapRouter.swapExactTokensForTokens(expand_amount, 1E18, path1, address(this), 1);
            elp_amount = amounts[1];

            if(elc_risk_reserve >= expand_amount) {
                elc_risk_reserve -= expand_amount;
            } else {
                elc_reserve -= (expand_amount - elc_risk_reserve);
                elc_risk_reserve = 0;
            }
            elp_risk_reserve += elp_amount;
        } else {
            // lr > 70, can not expand
            // cycle time is origin called block, can expand once in one day.
            if(lr <= 70) {
                if(in_cycle_flag == false) {
                    uint256 mint_amount = expand_amount - elc_reserve - elc_risk_reserve;
                    elc.mint(address(this), mint_amount);
                    elc_risk_reserve += mint_amount * 5 / 100;
                    amounts = swapRouter.swapExactTokensForTokens((mint_amount * 5 / 100), 1E18, path1, address(this), 1);
                    elp_amount = amounts[1];
                    elp_risk_reserve += elp_amount;

                    // liquidity miner for elc
                    uint256 elc_to_users = mint_amount * 95 /100;
                    acc_reward_elc_per_hc += elc_to_users/relp_hc_total;
                    elc_last_block = block.number;
                    last_expand_time = block.number;
                    emit ExpandCycle(block.number, elc_price, mint_amount);
                }

                amounts = swapRouter.swapExactTokensForTokens((elc_risk_reserve + elc_reserve), 1E18, path1, address(this), 1);
                elp_amount = amounts[1];
                elp_risk_reserve += elp_amount;
                elc_risk_reserve = 0;
                elc_reserve = 0;
            }
        }
    }

    // contract cycle. swap ELP to ELC
    function contraction_cycle() public returns(uint256) {
        bool in_cycle_flag = false;
        uint256 elp_price;
        uint256 elc_price;
        (elp_price, elc_price) = get_price();

        update_elc_aim();
        uint256 elc_down_limit = elcaim * 98 / 100;
     
        assert(elc_price < elc_down_limit);

        // 1 day gap, can expand once in one day.
        if(block.number < (last_contract_time + adjust_gap)) {
            in_cycle_flag = true;
        }

        uint256 usdt_per_elc;
        usdt_per_elc = query_swap_elc_price();

        // if swap price different to oracle price, use swap price
        // if swap price not low, do nothing
        assert(usdt_per_elc < elcaim * 98 * 100000000);

        uint256 elc_amount;
        // query amount from swap, how many elp to raise elc to 98% elcaim
        uint256 elp_need;
        elp_need = compute_elp_need();

        // call swap path
        address[] memory path2 = new address[](2);
        path2[0] = address(elpSwap);
        path2[1] = address(elcSwap);
        uint[] memory amounts = new uint[](2);

        if (elp_need <= elp_risk_reserve) {
            amounts = swapRouter.swapExactTokensForTokens(elp_need, 1E18, path2, address(this), 1);
            elc_amount = amounts[1];
            elp_risk_reserve -= elp_need;
            elc_risk_reserve += elc_amount;
        } else {
            uint256 elp_2percent = elp_reserve * 2 / 100;
            if(elp_need < (elp_risk_reserve + elp_2percent)) {
                amounts = swapRouter.swapExactTokensForTokens(elp_need, 1E18, path2, address(this), 1);
                elc_amount = amounts[1];
                elp_reserve -= (elp_need - elp_risk_reserve);
                elp_risk_reserve = 0;
                elc_risk_reserve += elc_amount;
            } else {
                amounts = swapRouter.swapExactTokensForTokens((elp_risk_reserve + elp_2percent), 1E18, path2, address(this), 1);
                elc_amount = amounts[1];
                elp_risk_reserve = 0;
                elp_reserve = 0;
                elc_risk_reserve += elc_amount;
            }
        }

        // cycle time is origin called block
        if(in_cycle_flag == false) {
            last_contract_time = block.number;
            emit ContractCycle(block.number, elc_price);
        }
    }

    // use ELC exchange get ELP, ELC in pool
    function exchange_ELC(uint256 elc_amount) public returns(uint256) {
        uint256 elp_price;
        uint256 elc_price;

        (elp_price, elc_price) = get_price();
        assert(elp_price > 0);
        
        uint256 lr = liability_ratio();

        if (lr <= 90) {
            uint256 elp_amount = elc_amount * elc_price / elp_price;
            if (elp_risk_reserve >= elp_amount)
            {
               assert(elc.transferFrom(msg.sender, address(this), elc_amount));
               elc_risk_reserve += elc_amount;
               assert(elp.transfer(msg.sender, elp_amount));
               elp_risk_reserve -= elp_amount;

               return (elp_amount);
            }
        }
        return 0;
    }

    // user withdraw rELP and send it to user address
    function withdraw_rELP(uint256 relp_amount) public {
        assert(relp_amount <= u_relp[msg.sender]);
        get_reward();
        relp_in_pool -= relp_amount;
        // part remove, all remove , can deal too
        u_relp_hc[msg.sender] = u_relp_hc[msg.sender] * (u_relp[msg.sender] - relp_amount) / u_relp[msg.sender];
        u_relp[msg.sender] -= relp_amount;
        // last system reward per hold-time
        start_sys_per_hc[msg.sender] = acc_reward_per_hc;
        start_sys_elc_per_hc[msg.sender] = acc_reward_elc_per_hc;

        relp.transferFrom(address(this), msg.sender, relp_amount);
    }

    // user add rELP to pool, liquidity miner
    function add_rELP(uint256 relp_amount) public {
        assert(relp.transferFrom(msg.sender, address(this), relp_amount));
        get_reward();
        relp_in_pool += relp_amount;
        u_relp[msg.sender] += relp_amount;
        // last system reward per hold-time
        start_sys_per_hc[msg.sender] = acc_reward_per_hc;
        start_sys_elc_per_hc[msg.sender] = acc_reward_elc_per_hc;
    }
    
    // add ELP to pool elp_risk_reserve
    function add_risk_reserve(uint256 elp_amount) public {
        assert(elp.transferFrom(msg.sender, address(this), elp_amount));
        elp_risk_reserve += elp_amount;
    }

    // compute the reward, when user operate add, remove, get reward
    function deal_acc_pool() public {
        if(block.number > last_block) {
            uint256 ph_reward = 2500000000000000000 * (block.number - last_block);
            relp_hc_total += relp_in_pool * (block.number - last_block);
            uint256 ph_reward_per_hc = ph_reward / relp_hc_total;
            acc_reward_per_hc += ph_reward_per_hc;
            last_block = block.number;
        }
    }

    // query：
    // compute the ELP amount get rELP amount and ELC amount
    function compute_add_ELP(uint256 elp_amount) public view returns(uint256, uint256) {
        uint256 elp_price;
        uint256 elc_price;
        uint256 relp_amount;
        uint256 elc_amount;

        (elp_price, elc_price) = get_price();
        
        uint256 lr = liability_ratio();
        uint256 relp_price = compute_relp_price();

        if (lr <= 30) {
            relp_amount = elp_amount * elp_price * (100 - lr) / relp_price / 100;
            elc_amount  = elp_amount * elp_price * lr / elc_price / 100; 
        } else {
            relp_amount = elp_amount * elp_price / relp_price;
            elc_amount  = 0; 
        }
        return (relp_amount, elc_amount);
    }

    // query:
    // estimate ELC value: value per ELC in swap
    function query_swap_elc_price() public view returns(uint256) {
        uint256 usdt_per_elc;
        uint256 a0;
        uint256 a1;
        uint256 t0;
        (a0, a1, t0) = elcSwap.getReserves();

        if(elc < usdt) {
            usdt_per_elc = UniswapV2Library.getAmountOut(1000000000000000000, a0, a1);
        } else {
            usdt_per_elc = UniswapV2Library.getAmountOut(1000000000000000000, a1, a0);
        }
        return usdt_per_elc;
    }

    // query:
    // compute elp_need by swap to swap
    function compute_elp_need() public view returns(uint256) {
        uint256 usdt_need;
        uint32 timeStamp;
        bool usdtToELC;
        // two step work to compute
        uint256 reserveUSDT;
        uint256 reserveELC;
        (reserveUSDT, reserveELC, timeStamp) = elcSwap.getReserves();
        (usdtToELC, usdt_need) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                1E18, (elcaim * 98 * 100000000),
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
    // get system liability Ratio(LR)
    function get_LR() public view returns(uint256) {
        return (liability_ratio());
    }

    // query:
    // get rELP price
    function get_relp_price() public view returns(uint256) {
        return (compute_relp_price());
    }

    // query:
    // get reserve
    function get_reserve() public view returns(uint256) {
        return elp_reserve;
    }

    // query:
    // get reserve ELC
    function get_elc_reserve() public view returns(uint256) {
        return elc_reserve;
    }

    // query:
    // get risk_reserve
    function get_risk_reserve() public view returns(uint256) {
        return elp_risk_reserve;
    }

    // query:
    // get risk_reserve ELC
    function get_elc_risk_reserve() public view returns(uint256) {
        return elc_risk_reserve;
    }

    // query:
    // get relp in pool amount of user
    function get_user_relp(address user) public view returns(uint256) {
        return u_relp[user];
    }

    // query:
    // get K factor
    function get_K() public view returns(uint256) {
        return k;
    }

    // set K factor
    function set_K(uint256 new_k) public onlyOwner {
        k = new_k;
        emit ChangeK(block.number, k);
    }

    // compute rELP price
    function compute_relp_price() public view returns(uint256) {
        uint256 elp_price;
        uint256 elc_price;
        uint256 relp_total;
        uint256 elc_total;

        (elp_price, elc_price) = get_price();

        relp_total = relp.totalSupply();
        elc_total  = elc.totalSupply();
        if (relp_total > 0) {
                return ((elp_reserve * elp_price).sub(elc_total * elc_price) / relp_total);
            } else {
                // set to proper number when deployed, never set zero
                return 100000000;
            }
    }

    function liability_ratio() public view returns(uint256) {
        uint256 lr;
        uint256 elp_price;
        uint256 elc_price;
        uint256 elc_total;

        // not only initial, anytime reserve down to zero should protect.
        if (elp_reserve == 0) {
            // set to proper number when deployed, must between 1~30. never set zero.
            return 20;
        }

        (elp_price, elc_price) = get_price();
        elc_total  = elc.totalSupply();
        lr =  elc_total * elc_price * 100 / (elp_reserve * elp_price);
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
    function update_elc_aim() public {
        uint256 span = (block.number).sub(elcaim_last_block) / 20000;
        if (span > 0) {
            for(uint256 i = 0; i < span; i++) {
                elcaim = elcaim * (100000 + k) / 100000;
            }
            elcaim_last_block = block.number;
        }
    }

    // get elp price from chainlink oracle
    function get_elp_price() public view returns (int) {
        uint80 roundID;
        int price;
        uint startedAt;
        uint timeStamp;
        uint80 answeredInRound;

        (
         roundID,
         price,
         startedAt,
         timeStamp,
         answeredInRound
        ) = elp_oracle.latestRoundData();
        return price;
    }
    
    // get elc price from chainlink oracle
    function get_elc_price() public view returns (int) {
        uint80 roundID;
        int price;
        uint startedAt;
        uint timeStamp;
        uint80 answeredInRound;

        (
         roundID,
         price,
         startedAt,
         timeStamp,
         answeredInRound
        ) = elc_oracle.latestRoundData();
        return price;
    }
    
    // get elp price and elc price, from oracle
    function get_price() public view returns(uint256, uint256) {
        uint256 elp_price = 0;
        uint256 elc_price = 0;

        if(get_elp_price() > 0) {
            elp_price = uint256(get_elp_price());
        }

        if(get_elc_price() > 0) {
            elc_price = uint256(get_elp_price());
        }

        return (elp_price, elc_price);
    }

    // get total hold-coin-time in pool
    function get_relp_hc() public view returns (uint256) {
        return relp_hc_total;
    }
}
