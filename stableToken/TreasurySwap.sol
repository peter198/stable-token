pragma solidity >=0.6.0 <0.8.5;
 
import "./libraries/BakerySwapRouter.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./libraries/FullMath.sol"; 
import "./libraries/Babylonian.sol"; 
 import "../libraries/SafeMath.sol";
 
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

    // swap, for ELC/USDT pair
    IUniswapV2Pair internal elcSwap;
    
    // swap, for ELP/USDT pair
    IUniswapV2Pair internal elpSwap;
    
    // global variables
    //  reserve elp
    uint256 private  elpReserveAmount = 0;
    
    // risk reserve elp
    uint256 private  elpRiskReserve = 0;
     
    // risk reserve elc
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
    // elp stake rewords
    mapping(address => uint256) public elpRewards;
    //elp stake rewords per coin 
    mapping(address => uint256) public elpRewardPerCoinPaid;
    // last change status block
    uint256 public lastExpandTime = 0;
    // last change status block
    uint256 public lastContractTime = 0;
   
    // voting parameters
    uint256 public against = 0;
    uint256 public approve = 0;
    uint256 public turnout = 0;
    uint256 public electorate = 0;
    uint256 public bgProposalBlock = 0;
    // proposal k target arrray
    uint256[] private proposalK; 
    // proposal sender arrray
    address[] private proposalSender;
    // against vote sender arrray
    address[] private againstSender;
    // approve vote sender arrray
    address[] private approveSender;
  
    event AddELP (address user,uint256 elp_amount,uint256 relp_amount,uint256 elc_amount);
    event WithdrawELP(address user, uint256 relp_amount,uint256 elc_amount,uint256 elp_amount);
    event ExpandCycle (uint256 blockno,uint256 elc_amount);
    event ContractCycle (uint256 blockno,uint256 start_price);
    event ChangeK (uint256 blockno,uint256 k);
    event AddRiskELP(address user,uint256 elpAmount);
  
    // update elcaim price by K Factor.
    modifier updateElcAim(){
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
        uint256 elc_price = querySwapElcPrice();
        uint256 elc_up_limit = elcAim.mul(102).div(100);
        require(elc_price > elc_up_limit,"elcPrice must great than upLimits");
     _;
    }
    // Determine if elc price overdown 0.98  
    modifier elcPriceOverDownlimit(){
        uint256 elc_price = querySwapElcPrice();
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
       require(liabilityRatio() < 70, 'lrOver: lr must < 70 ');
       _; 
    }   
    // get rElp rewards 
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
    
    constructor(address elpContract, 
                address elcContract,
                address relpContract,
                address usdtToken) public {
                
        elp = IERC20(elpContract);
        elc = IERC20(elcContract);
        rElp = IERC20(relpContract);
        usdt = IERC20(usdtToken);
        
        RewardRateBeginBlock = block.number;    
        elcaimLastBlock = block.number;
        lastContractTime = block.number;
        lastExpandTime = block.number;
        relpLastUpdateTime = block.number;
    }
    // shet swap address
    function setSwap(address elcUsdtPair, address elpUsdtPair) public onlyOwner {
        elcSwap = IUniswapV2Pair(elcUsdtPair);
        elpSwap = IUniswapV2Pair(elpUsdtPair);
    }
    // charge if user address is saved.
    function chargeAddrSaved()  private view returns (bool){
        for(uint i = 0;i < userArr.length; i++)
        {
            if(userArr[i] ==  msg.sender)
            {
                return true;
            }
        }
        return false;
    }
    
    // del the array element
    function deleteAddr(address account) private  returns (bool){
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
    function addRiskReserveElp(uint256 elpAmount) public onlyOwner returns(bool){
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
    function addRewardsElp(uint256 elpAmount) public onlyOwner  returns(bool){
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
    function addReserveElp(uint256 elpAmount) internal  returns(bool){
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(!ret)
        {
          return false;
        }  
       
        elpReserveAmount = elpReserveAmount + elpAmount;
     
        return true;
    }
    // get total reward amount 
    function getTotalRewardsElpAmount( ) public  view returns(uint256){
        return ELPReward;
    }
    // add ELP liquidity，returns rELP amount and ELC amount
    function addElp(uint256 elpAmount) public updateRewardELP returns(uint256 , uint256) {
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
        bool ret = false;
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
    // add elc to msg.sender
    function addElc(uint256 elcAmount) public  returns(bool){
        bool ret = elc.transferFrom( msg.sender,address(this), elcAmount);
        if(ret)
        {
             elcAmountArray[msg.sender] += elcAmount;
        }
        return ret;
    }
    // withdraw elc
    function withdrawElc(uint256 elcAmount) public  returns(bool){
        require(elcAmount <= elcAmountArray[msg.sender],"withdrawElc:withdraw amount must less than elcAmountArray hold!");
        bool ret = elc.transfer(msg.sender, elcAmount);
        elcAmountArray[msg.sender] -= elcAmount;   
        return ret;
    }
    // get the amount of elc belone to msg.sender
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
    // get the msg.sender's relp amounts
    function getRelpAmount() public view returns (uint256){
       return rElpAmountArray[msg.sender];
    }
    // for debugging use ,getblance of this contract's relp
    function getRelpPoolTotalAmount() public view onlyOwner returns (uint256){
       return rElp.balanceOf(address(this));
    }
    // for debugging use ,getblance of this contract's elp
    function getElpPoolTotalAmount() public view onlyOwner returns (uint256){
       return elp.balanceOf(address(this));
    }
    // for debugging use ,getblance of this contract's elc
    function getElcPoolTotalAmount() public view onlyOwner returns (uint256){
       return elc.balanceOf(address(this));
    }
    // swap token, for expansion and contraction
    function swapToken(bool elcBuyElpTag, uint256 amountIn) public returns (uint256){
        require( amountIn > 0);
        address[] memory path1 = new address[](3);
        uint256[] memory amounts = new uint256[](path1.length);
        if(elcBuyElpTag)
        {
            path1[0] = address(elc);
            path1[1] = address(usdt);
            path1[2] = address(elp);
            amounts = UniswapV2Library.getAmountsOut(elcSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elc),address(elcSwap),amountIn);    
        }else{
            path1[0] = address(elp);
            path1[1] = address(usdt);
            path1[2] = address(elc);
            amounts = UniswapV2Library.getAmountsOut(elcSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elp),address(elpSwap),amountIn); 
        }    
        for (uint256 i = 0; i < path1.length - 1; i++) 
        {
            (address input, address output) = (path1[i], path1[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                    ? (uint256(0), amountOut)
                    : (amountOut, uint256(0));
            address to = i < path1.length - 2 ? UniswapV2Library.pairFor(elcSwap.factory(), output, path1[i + 2]) : address(this);
               
            IBakerySwapPair(UniswapV2Library.pairFor(elcSwap.factory(), input, output)).swap(amount0Out, amount1Out, to);
        }
        return amounts[amounts.length -1];
    }
    // expand cycle. raise ELC, swap ELC to ELP
    function expansion() public 
    updateElcAim 
    lrLess70  
    elcPriceOverUplimit 
    expandInOneDayAg 
    returns(uint256) {
        uint256 elcSellAmount = expansionComputeElc();
        uint256 elpAmount = 0;

        if(elcRiskReserve >= elcSellAmount) {
            elpAmount = swapToken(true,elcSellAmount);
            elcRiskReserve -= elcSellAmount;
            elpRiskReserve += elpAmount;
        } else {
           uint256 mintAmount = 0;
           if(elcRiskReserve > 0)
           {
                elpAmount = swapToken(true,elcRiskReserve);
                elcRiskReserve =0;
                elpRiskReserve += elpAmount;
                mintAmount = elcSellAmount.sub(elcRiskReserve);
           } else  if(elcRiskReserve == 0){
               mintAmount = elcSellAmount;
           }
           
           elc.mint(address(this), mintAmount);
          
           elpAmount = swapToken(true,mintAmount.mul(5).div(100));
           elpRiskReserve += elpAmount;

            uint256  expandElcforRelp = mintAmount.mul(95).div(100);
            uint256 rElpCoinDayTotal = 0;
            if(userArr.length < 1)
            {
                elcRiskReserve += expandElcforRelp;
            }else{
            
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
        }    
        lastExpandTime = block.number;
        emit ExpandCycle(block.number, elcSellAmount);
        return elcSellAmount;
    }
    // contract cycle. swap ELP to ELC
    function contraction() public  
    elcPriceOverDownlimit 
    contractInOneDayAg 
    updateElcAim 
    returns(uint256) {
        uint256 elcAmount = 0;
        uint256 elpNeedSell = contractionComputeElpNeed();

        if (elpNeedSell <= elpRiskReserve) {
            elcAmount = swapToken(false,elpNeedSell);
            elpRiskReserve -= elpNeedSell;
            elcRiskReserve += elcAmount;
        } else {
            uint256 elp2percent = elpReserveAmount.mul(2).div(100);
            if(elpNeedSell < elpRiskReserve.add(elp2percent)) {
                elcAmount = swapToken(false,elpNeedSell);
                elpReserveAmount = elpRiskReserve.add(elpReserveAmount).sub(elpNeedSell);
                elpRiskReserve = 0;
                elcRiskReserve += elcAmount; 
            } else {
               elpNeedSell = elpRiskReserve.add(elp2percent);
               elcAmount = swapToken(false,elpNeedSell);
               elpRiskReserve = 0;
               elpReserveAmount -= elp2percent;
               elcRiskReserve += elcAmount;
            }
        }
    
       lastContractTime = block.number;
       emit ContractCycle(block.number, elpNeedSell);
       return elpNeedSell; 
    }

    // compute the ELP amount get rELP amount and ELC amount
    function computeRelpElcbyAddELP(uint256  elpAmount) public view returns(uint256 relpAmount, uint256 elcAmount) {
        uint256  elpPrice = querySwapElpPrice();
        uint256  elcPrice = querySwapElcPrice();
        uint256  lr = liabilityRatio();
       
        if (lr <= 30) {
             uint256   relpPrice = computeRelpPrice();
             if(relpPrice > 0)
             {
                 uint256  temp = elpAmount.mul(elpPrice).mul(100 - lr);
                 relpAmount = temp.div(relpPrice).div(100);
             }
             
             if(elcPrice > 0)
             {
                 elcAmount  = elpAmount.mul(elpPrice).mul(lr);
                 elcAmount  = elcAmount.div(elcPrice).div(100);
             }
        } else if (lr <= 90){
            uint256   relpPrice = computeRelpPrice();
            if(relpPrice > 0)
            {
                relpAmount = elpAmount.mul(elpPrice).div(relpPrice);
            }
            elcAmount  = 0; 
        } else if (lr > 90){
            uint256  relp_price_90 = computeRelpPrice90();
            if(relp_price_90 > 0)
            {
                relpAmount = elpAmount.mul(elpPrice).div(relp_price_90);
            }
            elcAmount  = 0; 
        }
        return (relpAmount, elcAmount);
    }
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
    // get the aimPrice at nearst blocktime
    function getAimPrice() public view returns(uint256){
        return elcAim;
    }
    // compute the selling elp amount, the buying elc amounts the betwixt usdt amount while contraction
    function contractionComputeElpNeed() public view returns(uint256 ) {
        uint256 elcPrice = querySwapElcPrice();
        require(elcPrice < elcAim.mul(98).div(100),"contractionComputeElpAndElc: true price less than aim");
        (uint256 reserve0, uint256 reserve1,) = elcSwap.getReserves();
        uint256 reserveUSDT = 0;
        uint256 reserveELC = 0;
        (address token0, ) = UniswapV2Library.sortTokens(address(elc), address(usdt));
        if(token0 == address(elc))
        {
            reserveELC = reserve0;
            reserveUSDT = reserve1;
        }else{
            reserveUSDT = reserve0;
            reserveELC = reserve1;
        }
         
        (bool usdtToELC, uint256 usdtNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                1E18, elcAim.mul(98).div(100),reserveUSDT, reserveELC);
       
        if (usdtNeed == 0) {
            return 0;
        }

        if(usdtToELC == false)
        {
            return 0;
        }
       
        uint256 reserveELP = 0;
        uint256 reserveUSDT2 = 0;
        (reserve0, reserve1, ) = elpSwap.getReserves();
        (token0, ) = UniswapV2Library.sortTokens(address(elp), address(usdt));
        if(token0 == address(elp))
        {
            reserveELP = reserve0;
            reserveUSDT2 = reserve1;
        }else{
            reserveUSDT2 = reserve0;
            reserveELP = reserve1;
        }
        
        if(usdtNeed > reserveUSDT2){
              return 0;
        }
        
        uint256 elpNeed = 0;
        elpNeed = UniswapV2Library.getAmountIn(usdtNeed, reserveELP, reserveUSDT2);
        return elpNeed;
    }
    // compute the selling elc amount, the buying elp amounts the betwixt usdt amount while expansion
    function expansionComputeElc() public view returns(uint256) {
        (uint256 reserve0, uint256 reserve1,) = elcSwap.getReserves();
       
        uint256 reserveUSDT;
        uint256 reserveELC;
        if(elcSwap.token0() == address(elc))
        {
            reserveELC = reserve0;
            reserveUSDT = reserve1;
        }else{
            reserveUSDT = reserve0;
            reserveELC = reserve1;
        }
        
        (bool elcToUsdt, uint256 elcNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                elcAim,1E18, reserveELC, reserveUSDT);
        
         if(elcToUsdt){
             return elcNeed;
         }
         return 0;
    }
    // get reserve elp amount
    function getElpReserve() public view returns(uint256) {
        return elpReserveAmount;
    }
    // get risk_reserve elp amount 
    function getElpRiskReserve() public view returns(uint256) {
        return elpRiskReserve;
    }
    // get risk_reserve ELC
    function getElcRiskReserve() public view returns(uint256) {
        return elcRiskReserve;
    }
    // get K factor
    function getK() public view returns(uint256) {
        return k;
    }
    // compute rELP price
    function computeRelpPrice() public view returns(uint256) {
       
        uint256 elp_price = querySwapElpPrice();
        uint256 elc_price = querySwapElcPrice();
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
        uint256 elp_price = querySwapElpPrice();
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
    // liability Ratio
    function liabilityRatio() public view returns(uint256) {
        // not only initial, anytime reserve down to zero should protect.
        if (elpReserveAmount == 0) {
            return 20;
        }

        uint256 lr;
        uint256 elp_price = querySwapElpPrice();
        uint256 elc_price = querySwapElcPrice();
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
    // reward per token
    function getElpRewardPerCoin() public view returns ( uint256  ) {
        
        uint256 span = (block.number - RewardRateBeginBlock).div(adjustGap);
        uint256 RatePerBlock = 0;
        if(span > 0)
        {
            RatePerBlock = ELPRewardRatePerBlock;
            for(uint256 i = 0; i < span; i++)
            {
               RatePerBlock = RatePerBlock.mul(99).div(100);
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
    // caculate rElp rewards
    function rewardELP() public view returns (uint256) {
        uint256 tmp = rElpAmountArray[msg.sender];
        return tmp
                .mul(getElpRewardPerCoin().sub(elpRewardPerCoinPaid[msg.sender]))
                .div(1e18)
                .add(elpRewards[msg.sender]);
    }

    //-------------------------------------k vote ------------------------//      
    // proposal k factor
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
   // get the first proposal 
    function getProposalTaget() public view returns(uint256){
       
        if(proposalK.length > 0)
        {
            return proposalK[0];
        }
        return 0;
    }
   // vote for approve
    function approveVote() public returns (bool){
        if( proposalK.length == 0 )
        {
          return false;
        }else if(proposalK[0] == 0)
        {
          return false;
        }
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
   // withdraw proposal 
    function withdrawProposal() public returns (bool) {
   
        if( proposalK.length == 0 )
        {
          return false;
        }else if(proposalK[0] == 0)
        {
          return false;
        }
        
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
   // vote for against
    function againstVote() public returns (bool){
        if( proposalK.length == 0 )
        {
          return false;
        }else if(proposalK[0] == 0)
        {
          return false;
        }
        
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
  // get vote result
    function votingResult() public returns (bool){
        
      if( proposalK.length == 0 )
      {
          return false;
      }else if(proposalK[0] == 0)
      {
          return false;
      }
      
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
}
