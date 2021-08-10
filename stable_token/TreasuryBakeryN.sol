// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.6.0 <0.8.5;
import "./libraries/BakerySwapRouter.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./libraries/UniswapV2Library.sol";
import "./libraries/UniswapV2LiquidityMathLibrary.sol";

library IterableMapping
{
  struct itmap
  {
    mapping(address => IndexValue) data;
    KeyFlag[] keys;
    uint size;
  }
  struct IndexValue { uint keyIndex; uint value; }
  struct KeyFlag { address key; bool deleted; }
  function insert(itmap storage self, address key, uint value) internal returns (bool replaced)
  {
    uint keyIndex = self.data[key].keyIndex;
    self.data[key].value = value;
    if (keyIndex > 0)
      return true;
    else
    { 
      self.data[key].keyIndex = self.keys.length;
      KeyFlag memory tmp = KeyFlag(key,false);  
      self.keys.push(tmp);  
      self.size++;
      return false;
    }
  }
  
  function popSort(itmap storage self) internal 
  {
       for(uint kIndex = self.keys.length; kIndex > 1; kIndex--)
       {
           if(self.data[self.keys[kIndex].key].value > self.data[self.keys[kIndex-1].key].value)
           {
               self.data[self.keys[kIndex].key].keyIndex = kIndex - 1;
               self.data[self.keys[kIndex - 1].key].keyIndex = kIndex;
           }
       }
  }
  
  function remove(itmap storage self, address key) internal returns (bool success)
  {
    uint keyIndex = self.data[key].keyIndex;
    if (keyIndex == 0)
      return false;
    delete self.data[key];
    self.keys[keyIndex - 1].deleted = true;
    self.size --;
  }
  function contains(itmap storage self, address key) internal view returns (bool)
  {
    return self.data[key].keyIndex > 0;
  }
  function iterate_start(itmap storage self) internal view returns (uint keyIndex)
  {
    return iterate_next(self, uint(-1));
  }
  function iterate_valid(itmap storage self, uint keyIndex) internal view returns (bool)
  {
    return keyIndex < self.keys.length;
  }
  function iterate_next(itmap storage self, uint keyIndex) internal view returns (uint r_keyIndex)
  {
    keyIndex++;
    while (keyIndex < self.keys.length && self.keys[keyIndex].deleted)
      keyIndex++;
    return keyIndex;
  }
  function iterate_get(itmap storage self, uint keyIndex) internal view returns (address key, uint value)
  {
    key = self.keys[keyIndex].key;
    value = self.data[key].value;
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
    // relp user array
    address[] private   userArr;
    
    uint256 private rewardRateBeginBlock = 0;
    uint256 private elcaimLastBlock = 0;
    // test
    uint256 constant private durationBlock = 100;
    uint256 constant private adjustGap = 28;
    uint256 constant private voteDuration = 20;
    uint256 constant private voteBaserelpAmount = 1;
    // test 
    // consant parms
    //uint256 constant private durationBlock = 20000;
    //uint256 constant private adjustGap = 28800;
    //uint256 constant private voteDuration = 201600;
    //uint256 constant private voteBaserelpAmount = 100;
    // ELP block revenue rate
    uint256 constant private elpRewardTotal = (2000000 * 1e18);
    uint256 private elpRewardPool = 0;
    uint256  constant private elpRewardFirstDay = (20000 * 1e18);
    uint256  private elpRewardRatePerBlock =  elpRewardFirstDay.div(adjustGap);
    // relp amount maparray that user put in pool
    mapping (address => uint256) private rElpAmountArray;
    // uRelp put in pool's block number 
    mapping (address => uint256) private rElpBgBlockArray;
    // uRelp put in pool's coin*day 
    mapping (address => uint256) private rElpBlockCoinDayArray;
    // elc amount maparray that user put in pool
    mapping (address => uint256) private elcAmountArray;
    // total rELP  in bankPool
    uint256 private rElpPoolTotal = 0;
    // system accumulative reward per relp hold-time
    uint256 private rewardElpPerCoinStored = 0;    
    // last relp change time 
    uint256 private relpLastUpdateTime = 0;
    // elp stake rewords
    mapping(address => uint256) private elpRewards;
    //elp stake rewords per coin 
    mapping(address => uint256) private elpRewardPerCoinPaid;
    // last change status block
    uint256 private lastExpandTime = 0;
    // last change status block
    uint256 private lastContractTime = 0;
    // voting parameters
    uint256 private against = 0;
    uint256 private approve = 0;
    uint256 private turnout = 0;
    uint256 private bgProposalBlock = 0;
    // proposal k target arrray
    IterableMapping.itmap private  proposalKmap;
    address[] private voterArray;
  
    event AddELP (address user,uint256 elp_amount,uint256 relp_amount,uint256 elc_amount);
    event WithdrawELP(address user, uint256 relp_amount,uint256 elc_amount,uint256 elp_amount);
    event ExpandCycle (uint256 blockno,uint256 elc_amount);
    event ContractCycle (uint256 blockno,uint256 start_price);
    event ChangeK (uint256 blockno,uint256 k);
    event AddRiskELP(address user,uint256 elpAmount);
    event AddRewardsELP(address user,uint256 elpAmount);
    event AddReserveELP(address user,uint256 elpAmount);
    event AddElcEvent(address user,uint256 elcAmount);
    event AddRelpEvent(address user,uint256 amount);
    event withdrawELCevent(address user,uint256 amount);
    event withdrawRelpevent(address user,uint256 amount);
    event withdrawElpevent(address user,uint256 amount); 
    // update elcaim price by K Factor.
    modifier updateElcAim(){
       votingResult();  
       if((block.number).sub(elcaimLastBlock) >= durationBlock){
           elcAim =  caculateElcAim();
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
        elpRewardRatePerBlock = caculateRatePerBlock(); 
        rewardElpPerCoinStored = getElpRewardPerCoin();
        relpLastUpdateTime = block.number;
        elpRewardPerCoinPaid[msg.sender] = rewardElpPerCoinStored;
        rewardRateBeginBlock = block.number;
        uint256 rewardTmp = rewardELP();
        if(elpRewardPool >=  rewardTmp)
        {  
            elpRewards[msg.sender] += rewardTmp; 
            elpRewardPool -= elpRewards[msg.sender];
        }
        _;
    }
    
    constructor (address elpContract, 
                address elcContract,
                address relpContract,
                address usdtToken) public {
        elp = IERC20(elpContract);
        elc = IERC20(elcContract);
        rElp = IERC20(relpContract);
        usdt = IERC20(usdtToken);
        rewardRateBeginBlock = block.number;    
        elcaimLastBlock = block.number;
        lastContractTime = block.number;
        lastExpandTime = block.number;
        relpLastUpdateTime = block.number;
    }
    
     // shet swap address
    function getElcFactory() external view returns(address) {
       address fac = elcSwap.factory();
       return fac;
    }
    // shet swap address
    function setSwap(address elcUsdtPair, address elpUsdtPair) external onlyOwner {
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
    // add ELP liquidity，for Risk Reserve 
    function addRiskReserveElp(uint256 elpAmount) external onlyOwner returns(bool){
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(ret)
        {
          elpRiskReserve = elpRiskReserve.add(elpAmount);
          emit AddRiskELP(msg.sender, elpAmount); 
        }
        return ret;
    }
    // add ELP liquidity，for Rewards 
    function addRewardsElp(uint256 elpAmount) external onlyOwner  returns(bool){
        require(elpAmount > 0, "elp amount must > 0");
        require(elpRewardPool.add(elpAmount) < elpRewardTotal, "reward elp amount must < totalreward");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(ret)
        {
          elpRewardPool= elpRewardPool.add(elpAmount);
          emit AddRewardsELP(msg.sender, elpAmount); 
        }
        return ret;
    }
    // add ELP liquidity to system
    function addReserveElp(uint256 elpAmount) internal  returns(bool){
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        if(ret)
        {
             elpReserveAmount = elpReserveAmount.add(elpAmount); 
             emit AddReserveELP(msg.sender, elpAmount);
        }
        return ret;
    }
    // get total reward amount 
    function getTotalRewardsElpAmount() external  view returns(uint256){
        return elpRewardPool;
    }
    // add ELP liquidity，returns rELP amount and ELC amount
    function addElp(uint256 elpAmount) external updateRewardELP returns(uint256 , uint256) {
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = addReserveElp(elpAmount);
        if(!ret)
        {
          return (0,0);
        }
        uint256 relpAmount = 0;
        uint256 elcAmount = 0;
        (relpAmount, elcAmount) = computeRelpElcbyAddELP(elpAmount);
        if (elcAmount > 0) {
           ret = elc.mint(address(this), elcAmount);
           require(ret  == true, "addElp:elc.mint must return true");
           elcAmountArray[msg.sender] += elcAmount;
        }
        if (relpAmount > 0) {
            ret = rElp.mint(address(this), relpAmount);
            require(ret  == true, "addElp:rElp.mint must return true");
           
            if(rElpBgBlockArray[msg.sender] > 0)
            {
               rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add( rElpAmountArray[msg.sender].mul(block.number.sub(rElpBgBlockArray[msg.sender])) );
            }else{
               rElpBlockCoinDayArray[msg.sender] = 0;
            }
            rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].add(relpAmount);
            rElpPoolTotal = rElpPoolTotal.add(relpAmount);
            rElpBgBlockArray[msg.sender] = block.number;
        } 
        bool isSaved = chargeAddrSaved();
        if(!isSaved)
        {
            userArr.push(msg.sender);
        }
        emit AddELP(msg.sender, elpAmount, relpAmount, elcAmount);
        return (relpAmount, elcAmount);
    }
    // withdraw elp，
    function withdrawElp(uint256 elpAmount) external updateRewardELP lrLess90 returns(bool) {
        require(elpAmount > 0, 'WithdrawElp: elpAmount must > 0 ');
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        require(elpRewardPool > elpRewards[msg.sender],"WithdrawElp: ELPReward must > elpRewards[msg.sender]");
        bool ret = false;
        if(elpAmount < elpRewards[msg.sender])
        {
            elpRewards[msg.sender] -= elpAmount;
            ret = elp.transfer(msg.sender, elpAmount);
            require(ret == true,"withdrawElp:elp.transfer must succ !");
        }
        uint256 tmpElpNeed = elpAmount.sub(elpRewards[msg.sender]);
        uint256 elcNeed = 0;
        uint256 relpNeed = 0;
     
        (elcNeed,relpNeed) = computeRelpElcbyWithdrawELP(tmpElpNeed);
        require((elcAmountArray[msg.sender]  >= elcNeed)  && (rElpAmountArray[msg.sender]  >= relpNeed),"withdrawElp:must have enough elc and relp!");
        elc.burn(elcNeed);
        elcAmountArray[msg.sender] = elcAmountArray[msg.sender].sub(elcNeed);
        rElp.burn(relpNeed);
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == 0)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
             deleteAddr(msg.sender);
        }else{
             rElpBlockCoinDayArray[msg.sender] =  rElpBlockCoinDayArray[msg.sender].add( (rElpAmountArray[msg.sender].sub(relpNeed)).mul(block.number.sub(rElpBgBlockArray[msg.sender])));
        }
        rElpBgBlockArray[msg.sender] = block.number;
        rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].sub(relpNeed);
        rElpPoolTotal = rElpPoolTotal.sub(relpNeed);
        elpReserveAmount = elpReserveAmount.sub(tmpElpNeed); 
        ret = elp.transfer(msg.sender, elpAmount);
        require(ret == true,"withdrawElp:elp.transfer must succ !");
        elpRewards[msg.sender] = 0; 
        emit withdrawElpevent(msg.sender,elpAmount); 
        return ret;
    }
    // add elc to msg.sender
    function addElc(uint256 elcAmount) external  returns(bool){
        require(elcAmount > 0,"addElc:elcAmount > 0");
        bool ret = elc.transferFrom( msg.sender,address(this), elcAmount);
        if(ret)
        {
             elcAmountArray[msg.sender] = elcAmountArray[msg.sender].add( elcAmount);
             emit AddElcEvent(msg.sender, elcAmount); 
        }
        return ret;
    }
    // withdraw elc
    function withdrawElc(uint256 elcAmount) external  returns(bool){
        require(elcAmount <= elcAmountArray[msg.sender],"withdrawElc:elcAmount <= elcAmountArray[msg.sender]");
        elcAmountArray[msg.sender] = elcAmountArray[msg.sender].sub(elcAmount); 
        bool ret = elc.transfer(msg.sender, elcAmount);
        require(ret == true,"withdrawElc:transfer elc must succ");
        emit withdrawELCevent(msg.sender, elcAmount); 
        return ret;
    }
    // get the amount of elc belone to msg.sender
    function getElcAmount() external view returns (uint256){
        return elcAmountArray[msg.sender];
    }
    // user withdraw rELP and send it to user address
    function withdrawRELP(uint256 relpAmount)  external updateRewardELP returns(bool){
        require(relpAmount <= rElpAmountArray[msg.sender],"withdrawRELP:withdraw amount must < rElpAmountArray hold!");
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == relpAmount)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
             deleteAddr(msg.sender);
        }else{
             rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add((rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender])));
        }
        rElpBgBlockArray[msg.sender] = block.number;
        rElpAmountArray[msg.sender] =  rElpAmountArray[msg.sender].sub(relpAmount);
        rElpPoolTotal = rElpPoolTotal.sub(relpAmount);
        bool ret = rElp.transfer(msg.sender, relpAmount);
        require(ret == true,"withdrawRELP:transfer relp must succ");
        emit withdrawRelpevent(msg.sender, relpAmount); 
        return ret;
    }
    // user add rELP to pool, liquidity miner
    function addRELP(uint256 relpAmount) external updateRewardELP returns(bool){
       require(relpAmount > 0,"addRELP:relpAmount >0 ");
        bool ret = rElp.transferFrom(msg.sender, address(this), relpAmount);
        if(ret)
        {
            rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add( (rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender])));
            rElpBgBlockArray[msg.sender] = block.number;
            rElpPoolTotal = rElpPoolTotal.add( relpAmount);
            rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].add(relpAmount);
            bool isSaved = chargeAddrSaved();
            if(!isSaved)
            {
                 userArr.push(msg.sender);
            }
            emit AddRelpEvent(msg.sender, relpAmount); 
        }    
         return ret;
    }
    // get the msg.sender's relp amounts
    function getRelpAmount() external view returns (uint256){
       return rElpAmountArray[msg.sender];
    }
    // for debugging use ,getblance of this contract's relp
    function getRelpPoolTotalAmount() external view onlyOwner returns (uint256){
       return rElp.balanceOf(address(this));
    }
    // for debugging use ,getblance of this contract's elp
    function getElpPoolTotalAmount() external view onlyOwner returns (uint256){
       return elp.balanceOf(address(this));
    }
    // for debugging use ,getblance of this contract's elc
    function getElcPoolTotalAmount() external view onlyOwner returns (uint256){
       return elc.balanceOf(address(this));
    }
    // swap token, for expansion and contraction
    function swapToken(bool elcBuyElpTag, uint256 amountIn) internal returns (uint256){
        require( amountIn > 0);
        address[] memory path1 = new address[](3);
        uint256[] memory amounts = new uint256[](path1.length);
        if(elcBuyElpTag)
        {
            path1[0] = address(elc);
            path1[1] = address(usdt);
            path1[2] = address(elp);
            amounts = BakerySwapLibrary.getAmountsOut(elcSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elc),address(elcSwap),amountIn);    
        }else{
            path1[0] = address(elp);
            path1[1] = address(usdt);
            path1[2] = address(elc);
            amounts = BakerySwapLibrary.getAmountsOut(elpSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elp),address(elpSwap),amountIn); 
        }    
        for (uint256 i = 0; i < path1.length - 1; i++) 
        {
            (address input, address output) = (path1[i], path1[i + 1]);
            (address token0, ) = BakerySwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                    ? (uint256(0), amountOut)
                    : (amountOut, uint256(0));
            address to = i < path1.length - 2 ? BakerySwapLibrary.pairFor(elcSwap.factory(), output, path1[i + 2]) : address(this);
            IBakerySwapPair(BakerySwapLibrary.pairFor(elcSwap.factory(), input, output)).swap(amount0Out, amount1Out, to);
        }
        return amounts[amounts.length -1];
    }
    // expand cycle. raise ELC, swap ELC to ELP
    function expansion() external 
    updateElcAim 
    lrLess70  
    elcPriceOverUplimit 
    expandInOneDayAg 
    returns(uint256) {
        lastExpandTime = block.number;
        uint256 elcSellAmount = expansionComputeElc();
        uint256 elpAmount = 0;
        if(elcRiskReserve >= elcSellAmount) {
            elcRiskReserve -= elcSellAmount;
            elpAmount = swapToken(true,elcSellAmount);
            elpRiskReserve += elpAmount;
        } else {
           uint256 mintAmount = 0;
           uint256 temp = elcRiskReserve;
           if(elcRiskReserve > 0)
           {
               elcRiskReserve =0;
               elpAmount = swapToken(true,temp);
               elpRiskReserve += elpAmount;
               mintAmount = elcSellAmount.sub(temp);
           } else  if(elcRiskReserve == 0){
               mintAmount = elcSellAmount;
           }
           require(elc.mint(address(this), mintAmount),"expansion:elc.mint fun must succ!");
           elpAmount = swapToken(true,mintAmount.mul(5).div(100));
           elpRiskReserve += elpAmount;
           uint256  expandElcforRelp = mintAmount.mul(95);
           uint256 rElpCoinDayTotal = 0;
           if(userArr.length < 1)
           {
                elcRiskReserve += expandElcforRelp.div(100);
           }else{
                for(uint i = 0;i < userArr.length; i++)
                {
                   rElpBlockCoinDayArray[userArr[i]] += (rElpAmountArray[userArr[i]]).mul(block.number - rElpBgBlockArray[userArr[i]]);
                   rElpCoinDayTotal += rElpBlockCoinDayArray[userArr[i]];
                }
                if(expandElcforRelp > 0 && rElpCoinDayTotal > 0)
                {
                   for(uint i = 0;i < userArr.length; i++)
                   {
                      elcAmountArray[userArr[i]] += expandElcforRelp.mul(rElpBlockCoinDayArray[userArr[i]]).div(rElpCoinDayTotal).div(100);
                      rElpBgBlockArray[userArr[i]] = block.number;
                      rElpBlockCoinDayArray[userArr[i]]  = 0;
                   }
               }
           }
        }    
       
        emit ExpandCycle(block.number, elcSellAmount);
        return elcSellAmount;
    }
    // contract cycle. swap ELP to ELC
    function contraction() external  
    elcPriceOverDownlimit 
    contractInOneDayAg 
    updateElcAim 
    returns(uint256) {
        uint256 elcAmount = 0;
        uint256 elpNeedSell = contractionComputeElpNeed();
        lastContractTime = block.number;
        if (elpNeedSell <= elpRiskReserve) {
            elpRiskReserve -= elpNeedSell;
            elcAmount = swapToken(false,elpNeedSell);
            elcRiskReserve += elcAmount;
        } else {
            uint256 elp2percent = elpReserveAmount.mul(2).div(100);
            if(elpNeedSell < elpRiskReserve.add(elp2percent)) {
                elpReserveAmount = elpRiskReserve.add(elpReserveAmount).sub(elpNeedSell);
                elpRiskReserve = 0;
                elcAmount = swapToken(false,elpNeedSell);
                elcRiskReserve += elcAmount; 
            } else {
               elpNeedSell = elpRiskReserve.add(elp2percent);
               elpRiskReserve = 0;
               elpReserveAmount -= elp2percent;
               elcAmount = swapToken(false,elpNeedSell);
               elcRiskReserve += elcAmount;
            }
        }
       emit ContractCycle(block.number, elpNeedSell);
       return elpNeedSell; 
    }
    // compute the ELP amount get rELP amount and ELC amount
    function computeRelpElcbyAddELP(uint256  elpAmount) internal view returns(uint256 relpAmount, uint256 elcAmount) {
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
    // caculate elc and relp amount while withdraw elp
   function computeRelpElcbyWithdrawELP(uint256  elpAmount) internal view returns(uint256 relpAmount, uint256 elcAmount){
        uint256  elpPrice = querySwapElpPrice();
        uint256  elcPrice = querySwapElcPrice();
        uint256  lr = liabilityRatio();
        uint256   relpPrice = computeRelpPrice();  
        if(lr < 90)
         {
           relpAmount = elpPrice.mul(elpAmount).mul(100 - lr).div(100).div(relpPrice);
           elcAmount = elpPrice.mul(elpAmount).mul(lr).div(elcPrice).div(100);    
         }
   }
    // estimate ELC value: value per ELC in swap
    function querySwapElcPrice() internal view returns(uint256) {
        uint256 usdtPerElc;
        uint256 a0;
        uint256 a1;
        uint256 t0;
        (a0, a1, t0) = elcSwap.getReserves();
        if(elc < usdt) {
            usdtPerElc = BakerySwapLibrary.getAmountOut(1E18, a0, a1);
        } else {
            usdtPerElc = BakerySwapLibrary.getAmountOut(1E18, a1, a0);
        }
        return usdtPerElc;
    }
    // estimate ELC value: value per ELC in swap
    function querySwapElpPrice() internal view returns(uint256) {
        uint256 usdtPerElp;
        uint256 a0;
        uint256 a1;
        uint256 t0;
        (a0, a1, t0) = elpSwap.getReserves();
        if(elp < usdt) {
            usdtPerElp = BakerySwapLibrary.getAmountOut(1E18, a0, a1);
        } else {
            usdtPerElp = BakerySwapLibrary.getAmountOut(1E18, a1, a0);
        }
        return usdtPerElp;
    }
    // get the aimPrice at nearst blocktime
    function getAimPrice() public view returns(uint256){
       uint256 tempElcAim = elcAim; 
       if((block.number).sub(elcaimLastBlock) >= durationBlock)
       {
           tempElcAim =  caculateElcAim();
       }
       return tempElcAim;
    }
    // compute the selling elp amount, the buying elc amounts the betwixt usdt amount while contraction
    function contractionComputeElpNeed() internal view returns(uint256 ) {
        uint256 elcPrice = querySwapElcPrice();
        require(elcPrice < elcAim.mul(98).div(100),"contractionComputeElpAndElc: true price less than aim");
        (uint256 reserve0, uint256 reserve1,) = elcSwap.getReserves();
        uint256 reserveUSDT = 0;
        uint256 reserveELC = 0;
        (address token0, ) = BakerySwapLibrary.sortTokens(address(elc), address(usdt));
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
        if (usdtNeed == 0 || !usdtToELC) {
            return 0;
        }
        uint256 reserveELP = 0;
        uint256 reserveUSDT2 = 0;
        (reserve0, reserve1, ) = elpSwap.getReserves();
        (token0, ) = BakerySwapLibrary.sortTokens(address(elp), address(usdt));
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
        elpNeed = BakerySwapLibrary.getAmountIn(usdtNeed, reserveELP, reserveUSDT2);
        return elpNeed;
    }
    // compute the selling elc amount, the buying elp amounts the betwixt usdt amount while expansion
    function expansionComputeElc() internal view returns(uint256) {
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
    function getElpReserve() external view returns(uint256) {
        return elpReserveAmount;
    }
    // get risk_reserve elp amount 
    function getElpRiskReserve() external view returns(uint256) {
        return elpRiskReserve;
    }
    // get risk_reserve ELC
    function getElcRiskReserve() external view returns(uint256) {
        return elcRiskReserve;
    }
    // get K factor
    function getK() external view returns(uint256) {
        return k;
    }
    // compute rELP price
    function computeRelpPrice() internal view returns(uint256) {
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
    function computeRelpPrice90() internal view returns(uint256){
        uint256 elp_price = querySwapElpPrice();
        uint256 relp_total = rElp.totalSupply();
        if (relp_total > 0) {
             if(elpReserveAmount > 0  && relp_total > 0)
             {
                 return ((elpReserveAmount.mul(elp_price)).mul(10).div(relp_total)).div(100);
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
        uint256 lr = 0;
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
    function getElpRewardPerCoin() public view returns (uint256) {
        uint256 tmpRatePerBlock = caculateRatePerBlock();
        if (rElpPoolTotal == 0) 
        {
            return rewardElpPerCoinStored;
        }
        return         
            rewardElpPerCoinStored.add(
                    ((block.number)
                    .sub(relpLastUpdateTime))
                    .mul(tmpRatePerBlock)
                    .div(rElpPoolTotal)
       );
    }
    // caculate true reward rate.
    function caculateRatePerBlock() internal view returns(uint256){
        uint256 span = (block.number - rewardRateBeginBlock).div(adjustGap);
        uint256 ratePerBlock = elpRewardRatePerBlock;
        uint256 mulParm = 1;
        uint256 divParm = 1;
        uint256 temp = 10;
        while(span > 0){
            if(span > temp)  
            {
                for(uint256 i = 0; i < temp; i++){            
                   mulParm = mulParm.mul(99);
                   divParm = divParm.mul(100);
                }
                mulParm = mulParm.div(divParm);
                divParm =1;
                span = span.sub(temp); 
            }else{
                for(uint256 i = 0; i < span; i++){            
                    mulParm = mulParm.mul(99);
                    divParm = divParm.mul(100);
                }
                span = 0;
            }
        }
        ratePerBlock = ratePerBlock.mul(mulParm).div(divParm);
        return ratePerBlock;
    }
    // caculate rElp rewards
    function rewardELP() public view returns (uint256) {
        uint256 tmp = rElpAmountArray[msg.sender];
        return tmp
                .mul(getElpRewardPerCoin().sub(elpRewardPerCoinPaid[msg.sender]))
                .div(1e18)
                .add(elpRewards[msg.sender]);
    }
    // caculate elc aim price
    function caculateElcAim() internal view returns(uint256){
        uint256 span = (block.number).sub(elcaimLastBlock).div(durationBlock);
        uint256 tempK = 1;
        uint256 tempDiv = 1;
        uint256 temp = 10;
        while(span > 0){
           if(span > temp)  
           {
               for(uint256 i = 0; i < temp; i++){            
                   tempK = tempK.mul(100000 +k);
                   tempDiv = tempDiv.mul(100000);
                }
                tempK = tempK.div(tempDiv);
                tempDiv =1;
                span = span.sub(temp); 
            }else{
                for(uint256 i = 0; i < span; i++){            
                    tempK = tempK.mul(100000 +k);
                    tempDiv = tempDiv.mul(100000);
                }
                span = 0;
            }
        }
        return elcAim.mul(tempK).div(tempDiv);
    }
    //-------------------------------------k vote ------------------------//      
    // proposal k factor
    function proposal(uint256 detaK) external returns (bool) {
       require(detaK > 0,"proposal:detaK must > 0");
       require(rElpAmountArray[msg.sender] >= voteBaserelpAmount,"proposal:relp hold must > voteBaserelpAmount");
       require(bgProposalBlock == 0 || block.number.sub(bgProposalBlock) < voteDuration,"proposal:must in voteDuration or the first propose");
 
       if(IterableMapping.contains(proposalKmap, msg.sender))
       {
           return false;
       }
       
       IterableMapping.insert(proposalKmap, msg.sender,detaK);
      
      IterableMapping.popSort(proposalKmap);
       
       turnout += rElpAmountArray[msg.sender];
       approve += rElpAmountArray[msg.sender];
       
       if(bgProposalBlock == 0)
       {
           bgProposalBlock = block.number;
       }
       for(uint256 i = 0; i < voterArray.length; i++)
       {
            if(voterArray[i]== address(0))
            {
                voterArray[i] = msg.sender;
                return true;
            }
       }
       voterArray.push(msg.sender);
       return true;
    }
    // get the first proposal 
    function getProposalTaget() external view returns(uint256){
       require( proposalKmap.size > 0,"getProposalTaget:must have proposalK");
        (, uint256 value) = IterableMapping.iterate_get(proposalKmap, 1) ;
        return value;
    }
    // vote for approve
    function approveVote() external returns (bool){
        require(proposalKmap.size > 0,"approveVote:proposalK  must have element ");
        (, uint256 value) = IterableMapping.iterate_get(proposalKmap, 0) ;
        require(value > 0,"approveVote:proposalK first element must > 0 ");
        require(block.number - bgProposalBlock  > voteDuration  &&  block.number - bgProposalBlock < voteDuration.mul(2));
     
        for(uint256 i = 0; i < voterArray.length; i++)
        {
             if(voterArray[i] == msg.sender)
                return false;
        }
        
        turnout += rElpAmountArray[msg.sender];
        approve += rElpAmountArray[msg.sender];
   
        for(uint256 i = 0; i < voterArray.length; i++)
        {
            if(voterArray[i]== address(0))
              {
                 voterArray[i] = msg.sender;
                 return true;
              }
        }
        voterArray.push(msg.sender);
        return true;
    }
    // withdraw proposal 
    function withdrawProposal() external returns (bool) {
        require(proposalKmap.size > 0,"withdrawProposal:proposalK  must have element ");
        (, uint256 value) = IterableMapping.iterate_get(proposalKmap, 0) ;
        require(value > 0,"withdrawProposal:proposalK first element must > 0 ");
        require(block.number - bgProposalBlock  < voteDuration,"withdrawProposal: must in withdraw duration > 0 ");
        require(IterableMapping.contains(proposalKmap, msg.sender) ,"withdrawProposal:the msg.sender  must an proposaler");
        
        bool isProposalSender = IterableMapping.remove(proposalKmap, msg.sender);
        if(isProposalSender == false)
          return false;
          
         (,  value) = IterableMapping.iterate_get(proposalKmap, 0) ;  
        if(value > 0){
            if(bgProposalBlock == 0)
             {
                    bgProposalBlock = block.number;
             }
        }
        return true;
    }
    // vote for against
    function againstVote() external returns (bool){
       require(proposalKmap.size > 0,"againstVote:proposalK  must have element ");
       (, uint256 value) = IterableMapping.iterate_get(proposalKmap, 0) ;
       require(value > 0,"againstVote:proposalK first element must > 0 ");
       require(block.number - bgProposalBlock  < voteDuration || block.number - bgProposalBlock > voteDuration.mul(2)
                ,"withdrawProposal: must in withwithdraqdraw duration > 0 ");

        for(uint256 i = 0; i < voterArray.length; i++)
        {
             if(voterArray[i]==msg.sender)
                return false;
        }
         
        turnout += rElpAmountArray[msg.sender];
        against += rElpAmountArray[msg.sender];
    
        for(uint256 i = 0; i < voterArray.length; i++)
        {
            if(voterArray[i] == address(0))
            {
                voterArray[i] = msg.sender;
                return true;
            }
        }
        voterArray.push(msg.sender);
        return true;
    }
    // get vote result
    function votingResult() public returns (bool){
      elcAim =  getAimPrice();
      if( proposalKmap.size  == 0 )
      {
          return false;
      }
      (, uint256 value) = IterableMapping.iterate_get(proposalKmap, 0) ;
      if(value == 0)
      {
          return false;
      }
      if(bgProposalBlock > 0 &&  block.number - bgProposalBlock > voteDuration.mul(2))
      {
          return false;
      }
      bool votingRet = false;
      uint256 electorate = rElp.totalSupply();  
       if(turnout == 0)
       {
           turnout = 1;
       }
       uint256 agreeVotes = against.mul(against).div(turnout);
       uint256 disagreeVotes =  approve.mul(approve).div(electorate);
       if(agreeVotes > disagreeVotes)
       {
           k = value; 
           votingRet = true;
       }
       
       bgProposalBlock = 0;
       IterableMapping.remove(proposalKmap, msg.sender); 

       against = 0;
       approve = 0;
       turnout = 0;

       (, value) = IterableMapping.iterate_get(proposalKmap, 0) ;
       if(value > 0 && bgProposalBlock == 0){
          bgProposalBlock = block.number;
       }
       
       for(uint256 i = 0; i < voterArray.length; i++ )
       {
           voterArray[i] = address(0);
       } 
       return votingRet;
    }
    //check if msg.sender just an proposer in  voteDuration
    function checkProposaler(address proposaler) internal view returns (bool){
       return  IterableMapping.contains(proposalKmap, msg.sender);
    }
    //check if msg.sender voted in voteDuration
    function checkHasVote() external view returns (bool){
        for(uint256 i = 0; i < voterArray.length; i++)
        {
             if(voterArray[i] == msg.sender)
                return true;
        }
        return false;
    }
    // get the approve votes amounts
    function getApproveTotal()external view returns(uint256){
        return approve;
    }
    // get the against votes amounts
    function getAgainstTotal()external view returns(uint256){
        return against;
    }
}
