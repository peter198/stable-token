// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.5;
import "./utils/Ownable.sol";
import "./interfaces/IBEP20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Babylonian.sol"; 
import "./libraries/TransferHelper.sol"; 
import {IOracle} from './Oracle.sol';
import {BakerySwapLibrary} from './libraries/BakerySwapLibrary.sol';
import {IBakerySwapPair} from './interfaces/IBakerySwapPair.sol';
import "./libraries/UniswapV2LiquidityMathLibrary.sol";
import {Epoch} from './utils/Epoch.sol';

contract Treasury is Ownable {
    using SafeMath for uint256;
    // used token contracts
    IBEP20 internal elp;
    IBEP20 internal elc;
    IBEP20 internal rElp;
    IBEP20 internal usdt;

    // oracle contract
    address internal _elcOracle;
    address internal _elpOracle;  

    // swap, for ELC/USDT pair
    IBakerySwapPair internal _elcSwap;
    // swap, for ELP/USDT pair
    IBakerySwapPair internal _elpSwap;
    
    // global Reserve variables
    struct globalReserveElement{
        uint256   elpReserveAmount;  // user add to the sys elp total amount
        uint256   elpRiskReserve;   // elp risk reserve
        uint256   elcRiskReserve;   // elc risk reserve 
        uint256   elpRewardAmount; // reward elp amount ,you need add it while used out
    }
    globalReserveElement private _reserveGlobal;

    struct elcAimElement{ 
        uint256  elcAim ; // ELCaim price, decimal  
        uint256  k ;   // Anti-Inflation Factor 0.00005 
        uint256  elcaimLastBlock ;        // blockNum that elcaim last changed
    }
    elcAimElement private _elcAimParm;
    
    // test  for 1%， Shrink by 100
    uint256 constant private _durationBlock = 200; // elcAim change duration
    uint256 constant private _adjustGap = 288;   // a day blocks total amounts
    uint256 constant private _voteDuration = 2016;   // vote duration
    uint256 constant private _voteBaserelpAmount = 1; // vote user base relp amount msust larger than this 
    uint256 constant private _elpRewardTotal = (20000 * 1e18);
    uint256 constant private _elpRewardFirstDay = (200 * 1e18);
    // test 
   
    // consant parms
    // uint256 constant private _durationBlock = 20000;  // elcAim change duration
    // uint256 constant private _adjustGap = 28800;      // a day blocks total amounts
    // uint256 constant private _voteDuration = 201600;  // vote duration
    // uint256 constant private _voteBaserelpAmount = 100; // vote user base relp amount msust larger than this 
    // uint256 constant private _elpRewardTotal = (2000000 * 1e18);
    // uint256 constant private _elpRewardFirstDay = (20000 * 1e18);
    
    // expand record of this system
    struct expandRec
    {
      uint256 totalCoinDay;
      uint256 expandBlockNo;
      uint256 totalExpandElc;
    }
    expandRec[] private  _expandHisRec;
    // reward rate sturct 
    struct rewardRate{
        uint256  elpRewardRatePerBlock;
        uint256  elpRewardRateChgBlock;
    }
    rewardRate private _rewardParm;

    struct userInfo{
        uint256   lastTimeExpandRewordforUser;  // The last time for  user to  allocate the rewards during the expansion
        uint256   rElpAmount;   // relp amount maparray that user put in pool
        uint256   rElpBlockCoinDay;// uRelp  coin*day 
        uint256   elpRewards; // elp stake rewords
        uint256   elpRewardPerCoinPaid; // elp stake rewords per coin 
        uint256   elcAmount;  // elc amount maparray that user put in pool  
        uint256   rElpLastUpdateTime;  // the last time relp amount change  
    }
    mapping (address => userInfo) private _relpUserArray;
 
    struct rElpTotalAmountInfo
    {
        uint256  rElpPoolTotal;  // total rELP  in bankPool
        uint256  rElpCoinDayTotal;   // total rElpCoinDay  in bankPool
        uint256  relpTotalLastUpdateTime;  // last total relp change time 
    }
    rElpTotalAmountInfo  private  _rElpTotalParm;
  
    // system accumulative reward per relp hold-time
    uint256 private _rewardElpPerCoinStored = 0;    
    // last change status block
    uint256 private _lastExpandTime = 0;
    // last change status block
    uint256 private _lastContractTime = 0;
  
    // voting parameters
    struct votingElement{      
        uint256  against ;  // against votes amount
        uint256  approve ;  // approve votes amount
        uint256  turnout ;  // total votes amount
        uint256  bgProposalBlock ; // start proposal time     
        uint256  proposalK;  // proposal k target     
        address  proposalSender;   // proposal sender 
    }
    votingElement private _votingParm;
    
    // voter info
    struct voteInfo{
        bool vote;      //  voted or not
        uint256 blockNo; // voting time
    }
    // voter Map 
    mapping(address => voteInfo) private _voterMap;
   
    /* =================== Event =================== */
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
    
    /* =================== Modifier =================== */
    // update elcaim price by K Factor.
    modifier updateElcAim(){
       votingResult();  
       if((block.number).sub(_elcAimParm.elcaimLastBlock) >= _durationBlock){
           _elcAimParm.elcAim =  caculateElcAim();
           _elcAimParm.elcaimLastBlock = block.number;
       }
      _;
    }
    // Determine if elc price exceeds1.02
    modifier elcPriceOverUplimit(){
        uint256  elc_price = getOraclePrice(_elcOracle,address(elc));
        uint256 elc_up_limit = _elcAimParm.elcAim.mul(102).div(100);
        require(elc_price > elc_up_limit,"elcPrice must great than upLimits");
     _;
    }
    // Determine if elc price overdown 0.98  
    modifier elcPriceOverDownlimit(){
         uint256  elc_price = getOraclePrice(_elcOracle,address(elc));
        uint256 elc_down_limit = _elcAimParm.elcAim.mul(98).div(100);
        require(elc_price < elc_down_limit,"elcPrice must small than downLimits");
     _;
    }
    // judgment of Expansion
    modifier expandInOneDayAg(){
       require(block.number > (_lastExpandTime.add(_adjustGap)),"expansion: can expand once in one day");
     _;        
    }   
    // Judgment of systole
    modifier contractInOneDayAg(){
       require(block.number > (_lastContractTime.add(_adjustGap)),"expansion: can expand once in one day");
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
        _rewardElpPerCoinStored = getElpRewardPerCoin();
        uint256 rewardTmp = rewardELP();
        // must prepare enough elp amounts for staker rewards,
        if(_reserveGlobal.elpRewardAmount >= rewardTmp){
            _relpUserArray[msg.sender].elpRewards += rewardTmp; 
            _reserveGlobal.elpRewardAmount -= rewardTmp;
          }        
          _relpUserArray[msg.sender].elpRewardPerCoinPaid = _rewardElpPerCoinStored;
          _rewardParm.elpRewardRatePerBlock = caculateRate( block.number); 
          _rewardParm.elpRewardRateChgBlock = block.number;
        _;
    }
    // if elc expanded,get the els amounts to personal amout array
    modifier getExpandElc(){
        (uint256 expandElcAmount,  uint256 CoinDay, uint256 UpdateTime ,  
                                         uint256 LastTimeExpand) =  computeExpandElcBelongMe();
         _relpUserArray[msg.sender].rElpLastUpdateTime = UpdateTime;
         _relpUserArray[msg.sender].lastTimeExpandRewordforUser = LastTimeExpand;
         _relpUserArray[msg.sender].rElpBlockCoinDay = CoinDay;
        _relpUserArray[msg.sender].elcAmount += expandElcAmount;
        _;
    }
     modifier updatePrice {
         updateCashPrice();
         _;
    }
   
     /* ========== MUTABLE FUNCTIONS ========== */
    constructor(address elpContract, 
                address elcContract,
                address relpContract,
                address usdtToken) public {
        elp = IBEP20(elpContract);
        elc = IBEP20(elcContract);
        rElp = IBEP20(relpContract);
        usdt = IBEP20(usdtToken);
    
        _lastContractTime = block.number;
        _lastExpandTime = block.number;
       
        _rElpTotalParm.relpTotalLastUpdateTime = block.number;
        _rElpTotalParm.rElpPoolTotal = 0;      // total rELP  in bankPool
        _rElpTotalParm.rElpCoinDayTotal = 0;   // total rElpCoinDay  in bankPool
       
        _reserveGlobal.elpReserveAmount = 0;
        _reserveGlobal.elpRiskReserve  = 0;
        _reserveGlobal.elcRiskReserve = 0;
        _reserveGlobal.elpRewardAmount = 0;
       
        _votingParm.against = 0;  // against votes amount
        _votingParm.approve = 0;  // approve votes amount
        _votingParm.turnout = 0 ;  // total votes amount
        _votingParm.bgProposalBlock = 0 ; // start proposal time     
        _votingParm.proposalK = 0;  // proposal k target     
        _votingParm.proposalSender = address(0);   // proposal sender 
      
        _elcAimParm.elcAim = 1 * 1e18; // ELCaim price, decimal  
        _elcAimParm.k = 5;   // Anti-Inflation Factor 0.00005 
        _elcAimParm.elcaimLastBlock = block.number;

        _rewardParm.elpRewardRatePerBlock =  _elpRewardFirstDay.div(_adjustGap);
        _rewardParm.elpRewardRateChgBlock = block.number;
    }
    // get a day avarage price of elp 
    function getOraclePrice(address oracleAdr,address token) public view returns (uint256) {
        try IOracle(oracleAdr).consult(token, 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert('Treasury: failed to consult elp price from the oracle');
        }
    }
    // set swap address
    function setSwap(address elcUsdtPair, 
                     address elpUsdtPair, 
                     address elcOracleAddr,  
                     address elpOracleAddr) external onlyOwner {
        _elcSwap = IBakerySwapPair(elcUsdtPair);
        _elpSwap = IBakerySwapPair(elpUsdtPair);
        _elcOracle = elcOracleAddr;
        _elpOracle = elpOracleAddr;
    }
    // add ELP liquidity，for Risk Reserve 
    function addRiskReserveElp(uint256 elpAmount) external onlyOwner returns(bool ret){
        require(elpAmount > 0, "elp amount must > 0");
        ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        require(ret == true, "addRiskReserveElp:transferFrom msgSender to this must succ");
        _reserveGlobal.elpRiskReserve =  _reserveGlobal.elpRiskReserve.add(elpAmount);
        emit AddRiskELP(msg.sender, elpAmount); 
    }
    // add ELP liquidity，for Rewards 
    function addRewardsElp(uint256 elpAmount) external onlyOwner  returns(bool ret){
        require(elpAmount > 0, "elp amount must > 0");
        require(_reserveGlobal.elpRewardAmount.add(elpAmount) < _elpRewardTotal, "reward elp amount must < totalreward");
        ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        require(ret == true,"addRewardsElp:transferFrom msg.sender to this  must succ");
        _reserveGlobal.elpRewardAmount= _reserveGlobal.elpRewardAmount.add(elpAmount);
        emit AddRewardsELP(msg.sender, elpAmount); 
    }
    // add ELP liquidity to system
    function addReserveElp(uint256 elpAmount) internal  returns(bool ret){
        require(elpAmount > 0, "elp amount must > 0");
         ret = elp.transferFrom(msg.sender, address(this), elpAmount);
        require(ret == true,"addReserveElp:transferFrom msg.sender to this  must succ");
        _reserveGlobal.elpReserveAmount =  _reserveGlobal.elpReserveAmount.add(elpAmount); 
        emit AddReserveELP(msg.sender, elpAmount);
    }
    // get total reward amount 
    function getTotalRewardsElpAmount() external  view returns(uint256){
        return _reserveGlobal.elpRewardAmount;
    }
    // add ELP liquidity，returns rELP amount and ELC amount
    function addElp(uint256 elpAmount) external updatePrice updateRewardELP getExpandElc  returns(uint256  , uint256 ) {
        require(elpAmount > 0, "elp amount must > 0");
        (uint256 relpAmount,uint256 elcAmount) = computeRelpElcbyAddELP(elpAmount);
        if (relpAmount == 0) {
            return (0, 0); 
        }
        bool ret ;
        if (elcAmount > 0) {
           ret = elc.mint(msg.sender, elcAmount);
           require(ret  == true, "addElp:elc.mint must return true");
        }
        
        ret = rElp.mint(address(this), relpAmount);
        require(ret  == true, "addElp:rElp.mint must return true");
        // new relp user
        if(_relpUserArray[msg.sender].rElpAmount == 0){
             _relpUserArray[msg.sender].lastTimeExpandRewordforUser =  block.number;
        }
        
        // compute new coinday should add 
        uint256 newCoinDay = _relpUserArray[msg.sender].rElpAmount.mul( (block.number
                             .sub(_relpUserArray[msg.sender].rElpLastUpdateTime)).div(_adjustGap) ) ;
        _relpUserArray[msg.sender].rElpBlockCoinDay = _relpUserArray[msg.sender].rElpBlockCoinDay.add( newCoinDay );
        _rElpTotalParm.rElpCoinDayTotal += newCoinDay;

        _relpUserArray[msg.sender].rElpAmount = _relpUserArray[msg.sender].rElpAmount.add(relpAmount);
        _relpUserArray[msg.sender].rElpLastUpdateTime =  block.number;
        _rElpTotalParm.rElpPoolTotal += relpAmount;
        _rElpTotalParm.relpTotalLastUpdateTime =  block.number;
         
        ret = addReserveElp(elpAmount);
        require(ret == true, "addElp: addReserveElp must succ"); 
        emit AddELP(msg.sender, elpAmount, relpAmount, elcAmount);
        return (relpAmount, elcAmount);
    }
    // withdraw elp，
    function withdrawElp(uint256 elpAmount) external updateRewardELP getExpandElc updatePrice lrLess90  returns(bool) {
        require(elpAmount > 0, 'WithdrawElp: elpAmount must > 0 ');
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in _voteDuration!");
        bool ret = false;
        if(elpAmount < _relpUserArray[msg.sender].elpRewards)
        {
            _relpUserArray[msg.sender].elpRewards =  _relpUserArray[msg.sender].elpRewards.sub(elpAmount);
            ret = elp.transfer(msg.sender, elpAmount);
            require(ret == true,"withdrawElp:elp.transfer must succ !");
            return ret;
        }
        uint256 tmpElpNeed = elpAmount.sub(_relpUserArray[msg.sender].elpRewards);
        (uint256 relpNeed ,uint256 elcNeed) = computeRelpElcbyWithdrawELP(tmpElpNeed);
        require(( elc.balanceOf(msg.sender) >= elcNeed)  && (_relpUserArray[msg.sender].rElpAmount  >= relpNeed),
                  "withdrawElp:must have enough elc and relp!");
              
        elc.burnFrom(msg.sender, elcNeed);
        rElp.burn(relpNeed);

        // compute new coinday should add 
        uint256 newCoinDay = _relpUserArray[msg.sender].rElpAmount
                            .mul( (block.number.sub(_relpUserArray[msg.sender].rElpLastUpdateTime) ).div(_adjustGap) ) ;
        if(_relpUserArray[msg.sender].rElpAmount == relpNeed)
        {
             _relpUserArray[msg.sender].rElpBlockCoinDay = 0;
        }else{
              _relpUserArray[msg.sender].rElpBlockCoinDay = _relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( newCoinDay );
        }
        if( _rElpTotalParm.rElpPoolTotal == relpNeed)
        {
             _rElpTotalParm.rElpCoinDayTotal = 0;
        }else{
            _rElpTotalParm.rElpCoinDayTotal += newCoinDay; 
        }
       
        _relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        _relpUserArray[msg.sender].rElpAmount = _relpUserArray[msg.sender].rElpAmount.sub(relpNeed);
        _relpUserArray[msg.sender].elpRewards = 0;
        
        _rElpTotalParm.rElpPoolTotal = _rElpTotalParm.rElpPoolTotal.sub(relpNeed);
        _rElpTotalParm.relpTotalLastUpdateTime =  block.number;
        
        ret = elp.transfer(msg.sender, elpAmount);
        require(ret == true,"withdrawElp:elp.transfer must succ !");
        _reserveGlobal.elpReserveAmount =  _reserveGlobal.elpReserveAmount.sub(tmpElpNeed); 
        emit withdrawElpevent(msg.sender,elpAmount); 
        return ret;
    }
    // withdraw elc
    function withdrawElc(uint256 elcAmount) external  returns(bool){
        require(elcAmount <= _relpUserArray[msg.sender].elcAmount,"withdrawElc:elcAmount <= _relpUserArray[msg.sender].elcAmount");
        _relpUserArray[msg.sender].elcAmount = _relpUserArray[msg.sender].elcAmount.sub(elcAmount); 
        bool ret = elc.transfer(msg.sender, elcAmount);
        require(ret == true ,"withdrawElc:trasfer from this to user msust succ");
        emit withdrawELCevent(msg.sender, elcAmount); 
        return ret;
    }
    // user withdraw rELP and send it to user address
    function withdrawRELP(uint256 relpAmount)  external updateRewardELP getExpandElc returns(bool){
        require(relpAmount <= _relpUserArray[msg.sender].rElpAmount,"withdrawRELP:withdraw amount must < rElpAmount hold!");
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in _voteDuration!");
        // compute new coinday should add 
        uint256 newCoinDay = _relpUserArray[msg.sender].rElpAmount
                           .mul( (block.number.sub(_relpUserArray[msg.sender].rElpLastUpdateTime) ).div(_adjustGap) ) ;
        if(_relpUserArray[msg.sender].rElpAmount == relpAmount)
        {
             _relpUserArray[msg.sender].rElpBlockCoinDay = 0;
        }else{
             _relpUserArray[msg.sender].rElpBlockCoinDay = _relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( newCoinDay );
        }
        if( _rElpTotalParm.rElpPoolTotal == relpAmount)
        {
             _rElpTotalParm.rElpCoinDayTotal = 0;
        }else{
            _rElpTotalParm.rElpCoinDayTotal += newCoinDay; 
        }
       
        _relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        _relpUserArray[msg.sender].rElpAmount =  _relpUserArray[msg.sender].rElpAmount.sub(relpAmount);
        
        _rElpTotalParm.rElpPoolTotal = _rElpTotalParm.rElpPoolTotal.sub(relpAmount);
        _rElpTotalParm.relpTotalLastUpdateTime =  block.number;
       
        bool ret = rElp.transfer(msg.sender, relpAmount);
        require(ret == true,"withdrawRELP:rElp.transfer must succ");
        emit withdrawRelpevent(msg.sender, relpAmount); 
        return ret;
    }
    // user add rELP to pool, liquidity miner
    function addRELP(uint256 relpAmount) external updateRewardELP getExpandElc returns(bool ){
        require(relpAmount > 0,"addRELP:relpAmount >0 ");
        // compute new coinday shuld add 
        uint256 newCoinDay = _relpUserArray[msg.sender].rElpAmount
                          .mul( (block.number.sub(_relpUserArray[msg.sender].rElpLastUpdateTime) ).div(_adjustGap) ) ;
        _relpUserArray[msg.sender].rElpBlockCoinDay = _relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( newCoinDay );
        _rElpTotalParm.rElpCoinDayTotal += newCoinDay;
        _relpUserArray[msg.sender].rElpAmount = _relpUserArray[msg.sender].rElpAmount.add(relpAmount);
        _relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        _rElpTotalParm.rElpPoolTotal += relpAmount;
        _rElpTotalParm.relpTotalLastUpdateTime =  block.number;
        bool ret = rElp.transferFrom(msg.sender, address(this), relpAmount);
        require(ret == true,"addRELP:rElp.transfer to this must succ");
        emit AddRelpEvent(msg.sender, relpAmount); 
        return ret;
    }
    // update oracle token price
    function updateCashPrice() internal {
        if (Epoch(_elcOracle).callable()) {
            try IOracle(_elcOracle).update() {} catch {}
        }
        
        if (Epoch(_elpOracle).callable()) {
            try IOracle(_elpOracle).update() {} catch {}
        }
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
            amounts = BakerySwapLibrary.getAmountsOut(_elcSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elc),address(_elcSwap),amountIn);    
        }else{
            path1[0] = address(elp);
            path1[1] = address(usdt);
            path1[2] = address(elc);
            amounts = BakerySwapLibrary.getAmountsOut(_elpSwap.factory(),amountIn, path1);
            TransferHelper.safeTransfer(address(elp),address(_elpSwap),amountIn); 
        }    
        for (uint256 i = 0; i < path1.length - 1; i++) {
            (address input, address output) = (path1[i], path1[i + 1]);
            (address token0, ) = BakerySwapLibrary.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                    ? (uint256(0), amountOut)
                    : (amountOut, uint256(0));
            address to = i < path1.length - 2 ? BakerySwapLibrary.pairFor(_elcSwap.factory(), output, path1[i + 2]) : address(this);
            IBakerySwapPair(BakerySwapLibrary.pairFor(_elcSwap.factory(), input, output)).swap(amount0Out, amount1Out, to);
        }
        return amounts[amounts.length -1];
    }
    // compute elc amount belong to msg.sender while expand
    function computeExpandElcBelongMe() public view returns(uint256, uint256 ,uint256, uint256){
        uint256 tempLastUpdateTime = _relpUserArray[msg.sender].rElpLastUpdateTime;
        uint256 tempBlockCoinDay = _relpUserArray[msg.sender].rElpBlockCoinDay;
        uint256 tempLastTimeExpandRewordforUser = _relpUserArray[msg.sender].lastTimeExpandRewordforUser;
        uint256 expandElcAmount= 0;
        for(uint256 i = 0; i < _expandHisRec.length; i++)
        {
            uint caculateTime = _expandHisRec[i].expandBlockNo;
            if( tempLastTimeExpandRewordforUser >= caculateTime )
            {
               continue;
            }
            tempBlockCoinDay  +=  _relpUserArray[msg.sender].rElpAmount.mul( ( caculateTime.sub(tempLastUpdateTime) ).div(_adjustGap) );
            expandElcAmount += FullMath.mulDiv(tempBlockCoinDay, _expandHisRec[i].totalExpandElc, _expandHisRec[i].totalCoinDay);
            tempBlockCoinDay = 0;
            tempLastUpdateTime = caculateTime;
            tempLastTimeExpandRewordforUser = caculateTime;
        }
        return ( expandElcAmount, tempBlockCoinDay, tempLastUpdateTime , tempLastTimeExpandRewordforUser);
    }
    
    // expand cycle. raise ELC, swap ELC to ELP
    function expansion() external updatePrice updateElcAim lrLess70 elcPriceOverUplimit expandInOneDayAg  returns(uint256) {
        _lastExpandTime = block.number;
        uint256 elcSellAmount = expansionComputeElc();
        uint256 elpAmount = 0;
        if( _reserveGlobal.elcRiskReserve >= elcSellAmount) {
             _reserveGlobal.elcRiskReserve =  _reserveGlobal.elcRiskReserve.sub(elcSellAmount);
            elpAmount = swapToken(true,elcSellAmount);
            _reserveGlobal.elpRiskReserve += elpAmount;
        } else {
           uint256 mintAmount = 0;
           uint256 temp =  _reserveGlobal.elcRiskReserve;
           if( _reserveGlobal.elcRiskReserve > 0)
           {
               _reserveGlobal.elcRiskReserve = 0;
               elpAmount = swapToken(true,temp);
               _reserveGlobal.elpRiskReserve += elpAmount;
               mintAmount = elcSellAmount.sub(temp);
           } else  if( _reserveGlobal.elcRiskReserve == 0){
               mintAmount = elcSellAmount;
           }
           require(elc.mint(address(this), mintAmount),"expansion:elc.mint fun must succ!");
           elpAmount = swapToken(true,mintAmount.mul(5).div(100));
           _reserveGlobal.elpRiskReserve += elpAmount;
           _rElpTotalParm.rElpCoinDayTotal += _rElpTotalParm.rElpPoolTotal
                          .mul(  ( (block.number).sub(_rElpTotalParm.relpTotalLastUpdateTime) ).div(_adjustGap) );
           uint256  expandElcforRelp = FullMath.mulDiv(mintAmount,95,100);
           _expandHisRec.push(expandRec(_rElpTotalParm.rElpCoinDayTotal,block.number,expandElcforRelp ));
           _rElpTotalParm.rElpCoinDayTotal = 0;
           _rElpTotalParm.relpTotalLastUpdateTime = block.number;
        }
        emit ExpandCycle(block.number, elcSellAmount);
        return elcSellAmount;
    }
    // contract cycle. swap ELP to ELC
    function contraction() external updatePrice elcPriceOverDownlimit contractInOneDayAg  updateElcAim  returns(uint256) {
        uint256 elcAmount = 0;
        uint256 elpNeedSell = contractionComputeElpNeed();
        _lastContractTime = block.number;
        if (elpNeedSell <=  _reserveGlobal.elpRiskReserve) {
            _reserveGlobal.elpRiskReserve -= elpNeedSell;
            elcAmount = swapToken(false,elpNeedSell);
            _reserveGlobal.elcRiskReserve += elcAmount;
        } else {
            uint256 elp2percent =  _reserveGlobal.elpReserveAmount.mul(2).div(100);
            if(elpNeedSell < _reserveGlobal.elpRiskReserve.add(elp2percent)) {
                 _reserveGlobal.elpReserveAmount =  _reserveGlobal.elpRiskReserve.add( _reserveGlobal.elpReserveAmount).sub(elpNeedSell);
                 _reserveGlobal.elpRiskReserve = 0;
                 elcAmount = swapToken(false,elpNeedSell);
                 _reserveGlobal.elcRiskReserve += elcAmount; 
            } else {
                elpNeedSell = _reserveGlobal.elpRiskReserve.add(elp2percent);
                _reserveGlobal.elpRiskReserve = 0;
                _reserveGlobal.elpReserveAmount -= elp2percent;
                elcAmount = swapToken(false,elpNeedSell);
                _reserveGlobal.elcRiskReserve += elcAmount;
            }
        }
       emit ContractCycle(block.number, elpNeedSell);
       return elpNeedSell; 
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    // get the amount of elc belone to msg.sender
    function getElcAmount() external view returns (uint256){
        return _relpUserArray[msg.sender].elcAmount;
    }
    // get the msg.sender's relp amounts
    function getRelpAmount() external view returns (uint256){
       return _relpUserArray[msg.sender].rElpAmount;
    }
    // for debugging use ,getblance of this contract's relp
    function getRElpPoolTotalAmount() external view onlyOwner returns (uint256){
       return _rElpTotalParm.rElpPoolTotal;
    }
    // for debugging use ,getblance of this contract's elp
    function getElpPoolTotalAmount() external view onlyOwner returns (uint256){
       return (_reserveGlobal.elpReserveAmount + _reserveGlobal.elpRiskReserve + _reserveGlobal.elpRewardAmount);
    }
    // for debugging use ,getblance of this contract's elc
    function getElcPoolTotalAmount() external view onlyOwner returns (uint256){
       return elc.balanceOf(address(this));
    }
    // compute the ELP amount get rELP amount and ELC amount
    function computeRelpElcbyAddELP(uint256  elpAmount) public view returns(uint256 , uint256 ) {
        uint256  elcPrice = getOraclePrice(_elcOracle,address(elc));
        uint256  elpPrice  = getOraclePrice(_elpOracle,address(elp));
        uint256 relpAmount = 0;
        uint256 elcAmount = 0;
        uint256  lr = liabilityRatio();
        if (lr <= 30) {
           uint256   relpPrice = computeRelpPrice();
           relpAmount =  FullMath.mulDiv( elpAmount,elpPrice.mul(100 -lr),relpPrice.mul(100) );
           elcAmount =  FullMath.mulDiv( elpAmount,elpPrice.mul(lr),elcPrice.mul(100) );
        } else if (lr <= 90 && lr > 30){
            uint256   relpPrice = computeRelpPrice();
            relpAmount =  FullMath.mulDiv( elpAmount,elpPrice,relpPrice);
            elcAmount  = 0; 
        } else if (lr > 90){
            uint256  relpPrice90 = computeRelpPrice90();
            relpAmount =  FullMath.mulDiv( elpAmount,elpPrice,relpPrice90);
            elcAmount  = 0; 
        }
        return ( relpAmount,  elcAmount);
    }
    // caculate elc and relp amount while withdraw elp
    function computeRelpElcbyWithdrawELP(uint256  elpAmount) public view returns(uint256 , uint256 ){
        uint256  elcPrice = getOraclePrice(_elcOracle,address(elc));
        uint256  elpPrice  = getOraclePrice(_elpOracle,address(elp));
        uint256 relpAmount =0;
        uint256 elcAmount = 0;
        uint256  lr = liabilityRatio();
        uint256   relpPrice = computeRelpPrice();  
        if(lr < 90)
        {
           relpAmount =  FullMath.mulDiv( elpPrice,elpAmount.mul(100 -lr),relpPrice.mul(100) );
           elcAmount =  FullMath.mulDiv( elpPrice,elpAmount.mul(lr),elcPrice.mul(100) );  
        }
        return (relpAmount,elcAmount);
    }
    // get the aimPrice at nearst blocktime
    function getAimPrice() public view returns(uint256){
       uint256 tempElcAim = _elcAimParm.elcAim; 
       if((block.number).sub(_elcAimParm.elcaimLastBlock) >= _durationBlock){
           tempElcAim =  caculateElcAim();
       }
       return tempElcAim;
    }
    // compute the selling elp amount, the buying elc amounts the betwixt usdt amount while contraction
    function contractionComputeElpNeed() public view returns(uint256) {      
        uint256  elcPrice = getOraclePrice(_elcOracle,address(elc));
        require(elcPrice < _elcAimParm.elcAim.mul(98).div(100),"contractionComputeElpAndElc: true price less than aim");
        (uint256 reserve0, uint256 reserve1,) = _elcSwap.getReserves();
        uint256 reserveUSDT = 0;
        uint256 reserveELC = 0;
        (address token0, ) = BakerySwapLibrary.sortTokens(address(elc), address(usdt));
        if(token0 == address(elc)){
            reserveELC = reserve0;
            reserveUSDT = reserve1;
        }else{
            reserveUSDT = reserve0;
            reserveELC = reserve1;
        }
         
        (bool usdtToELC, uint256 usdtNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                1E18, _elcAimParm.elcAim.mul(98).div(100),reserveUSDT, reserveELC);
        if (usdtNeed == 0 || usdtToELC == false) {
            return 0;
        }

        uint256 reserveELP = 0;
        uint256 reserveUSDT2 = 0;
        (reserve0, reserve1, ) = _elpSwap.getReserves();
        (token0, ) = BakerySwapLibrary.sortTokens(address(elp), address(usdt));
        if(token0 == address(elp)){
            reserveELP = reserve0;
            reserveUSDT2 = reserve1;
        }else{
            reserveUSDT2 = reserve0;
            reserveELP = reserve1;
        }
        
        if(usdtNeed > reserveUSDT2){
              return 0;
        }
        
        return BakerySwapLibrary.getAmountIn(usdtNeed, reserveELP, reserveUSDT2);
    }
    // compute the selling elc amount, the buying elp amounts the betwixt usdt amount while expansion
    function expansionComputeElc() public view returns(uint256) {
       uint256  elcPrice = getOraclePrice(_elcOracle,address(elc));
       require(elcPrice > _elcAimParm.elcAim.mul(102).div(100),"contractionComputeElpAndElc: true price large than aim 102%");
        (uint256 reserve0, uint256 reserve1,) = _elcSwap.getReserves();
        uint256 reserveUSDT;
        uint256 reserveELC;
        if(_elcSwap.token0() == address(elc)){
            reserveELC = reserve0;
            reserveUSDT = reserve1;
        }else{
            reserveUSDT = reserve0;
            reserveELC = reserve1;
        }
        (bool elcToUsdt, uint256 elcNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
               1E18, _elcAimParm.elcAim, reserveELC, reserveUSDT);
         if(elcToUsdt){
             return elcNeed;
         }
         return 0;
    }
    // get reserve elp amount
    function getElpReserve() external view returns(uint256) {
        return  _reserveGlobal.elpReserveAmount;
    }
    // get risk_reserve elp amount 
    function getElpRiskReserve() external view returns(uint256) {
        return  _reserveGlobal.elpRiskReserve;
    }
    // get risk_reserve ELC
    function getElcRiskReserve() external view returns(uint256) {
        return  _reserveGlobal.elcRiskReserve;
    }
    // get K factor
    function getK() external view returns(uint256) {
        return _elcAimParm.k;
    }
    // compute rELP price
    function computeRelpPrice() public view returns(uint256) {
        uint256  elcPrice = getOraclePrice(_elcOracle,address(elc));
        uint256  elpPrice  = getOraclePrice(_elpOracle,address(elp));
        uint256 relpTotal = rElp.totalSupply();
        uint256 elcTotal  = elc.totalSupply();
        if (relpTotal == 0 || _reserveGlobal.elpReserveAmount == 0){
             return 1E18;  
        }
        (uint256 elpl, uint256 elph) = FullMath.fullMul(_reserveGlobal.elpReserveAmount, elpPrice);
        (uint256 elcl, uint256 elch) =  FullMath.fullMul(elcTotal, elcPrice); 
        if((elph > elch) || ( (elph == elch) && (elpl > elcl) ) )
        {
            uint256 relpPrice =  FullMath.mulDiv( _reserveGlobal.elpReserveAmount,elpPrice,relpTotal );
            relpPrice = relpPrice.sub( FullMath.mulDiv( elcTotal,elcPrice,relpTotal) );
            return relpPrice;  
        }
        return 1E18; 
    }
    // lr = 90%  prelp
    function computeRelpPrice90() public view returns(uint256){
       uint256  elp_price  = getOraclePrice(_elpOracle,address(elp));
       uint256 relp_total = rElp.totalSupply();
       if (relp_total == 0 || _reserveGlobal.elpReserveAmount == 0) {
           return   1E18; 
       }
       uint256 relpPrice =  FullMath.mulDiv( _reserveGlobal.elpReserveAmount,elp_price.mul(10),relp_total.mul(100) );
       return relpPrice;
    }
    // liability Ratio
    function liabilityRatio() public view returns(uint256) {
        // not only initial, anytime reserve down to zero should protect.
        if ( _reserveGlobal.elpReserveAmount == 0) {
            return 20;
        }
        uint256 lr = 0;      
        uint256  elc_price = getOraclePrice(_elcOracle,address(elc));
        uint256  elp_price  = getOraclePrice(_elpOracle,address(elp));
        uint256 elc_total = elc.totalSupply();
        
        if(elp_price > 0 &&  _reserveGlobal.elpReserveAmount > 0){
            lr = ( FullMath.mulDiv(elc_total.mul(100), elc_price,elp_price) ).div( _reserveGlobal.elpReserveAmount);
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
        uint256 tmpRatePerBlock = caculateAvgRatePerBlock(_rElpTotalParm.relpTotalLastUpdateTime);
        if (_rElpTotalParm.rElpPoolTotal == 0){
            return _rewardElpPerCoinStored;
        }
       return _rewardElpPerCoinStored.add(
                    (block.number - _rElpTotalParm.relpTotalLastUpdateTime)
                    .mul(tmpRatePerBlock)
                    .mul(1e18)
                    .div(_rElpTotalParm.rElpPoolTotal));
    }
    // caculate true reward rate.
    function caculateAvgRatePerBlock(uint256 updateTime) public view returns(uint256){
      require(block.number >= updateTime,"caculateAvgRatePerBlock: block.number must >= updateTime");
         uint256 rate = caculateRate(updateTime);
         uint256 span = (block.number.sub(updateTime)).div(_adjustGap); 
         uint256 avgRate = 0;
        if(span == 0){
             return rate;
        }
        uint256 temp = 10;
        uint256 aTemp = 0;
        uint256 sTotal = 0;
        while(span > 0){
            if(span > temp){
                aTemp = rate.mul(99**9).div( 100**9);
                sTotal = sTotal.add(rate.mul(100).sub(aTemp.mul(99)));
                rate = aTemp;
                span = span.sub(temp); 
            }else{
                aTemp = rate.mul(99**(span-1)).div( 100**(span -1));
                sTotal = sTotal.add(rate.mul(100).sub(aTemp.mul(99)));
                span = 0;
            }
        }
        avgRate = (sTotal.mul(_adjustGap)).add( aTemp.mul( block.number.mod(_adjustGap)) );
        avgRate = avgRate.div(block.number.sub(updateTime));
        return avgRate;
    }  
    // caculate true reward rate.
    function caculateRate(uint256 rateTime) public view returns(uint256){
        require(rateTime >= _rewardParm.elpRewardRateChgBlock,"caculateRate: time > rateChgblock");
        uint256 span = (rateTime - _rewardParm.elpRewardRateChgBlock).div(_adjustGap);
        uint256 rate = _rewardParm.elpRewardRatePerBlock;
        uint256 aTemp = rate;
        uint256 temp = 10;
        while(span > 0){
            if(span > temp){
                aTemp = rate.mul(99**9).div( 100**9);
                rate = aTemp;
                span = span.sub(temp); 
            }else{
                aTemp = rate.mul(99**(span-1)).div( 100**(span-1));
                span = 0;
            }
        }
        return aTemp;
    }
    // caculate rElp rewards
    function rewardELP() public view returns (uint256) {
        return _relpUserArray[msg.sender].rElpAmount
                .mul(getElpRewardPerCoin().sub(_relpUserArray[msg.sender].elpRewardPerCoinPaid))
                .div(1e18)
                .add(_relpUserArray[msg.sender].elpRewards);
    }
    // caculate elc aim price
    function caculateElcAim() public view returns(uint256){
        uint256 span = (block.number).sub(_elcAimParm.elcaimLastBlock).div(_durationBlock);
        uint256 tempK = 1;
        uint256 tempDiv = 1;
        uint256 temp = 10;
        while(span > 0){
           if(span > temp)  
           {
                tempK = tempK.mul( (100000 +_elcAimParm.k)**9 );
                tempDiv = tempDiv.mul(100000 ** 9);
                tempK = tempK.div(tempDiv);
                tempDiv =1;
                span = span.sub(temp); 
            }else{
                tempK = tempK.mul( (100000 +_elcAimParm.k)**(span -1) );
                tempDiv = tempDiv.mul(100000 ** (span -1));
                span = 0;
            }
        }
        return _elcAimParm.elcAim.mul(tempK).div(tempDiv);
    }
    
    /* ==========K VOTE FUNCTIONS ========== */
    // proposal k factor
    function proposal(uint256 detaK) external returns (bool) {
       require(detaK > 0,"proposal:detaK must > 0");
       require(_relpUserArray[msg.sender].rElpAmount >= _voteBaserelpAmount,"proposal:relp hold must > _voteBaserelpAmount");
       require(_votingParm.bgProposalBlock == 0 || (block.number - _votingParm.bgProposalBlock) < _voteDuration,
                                                                 "proposal:must in _voteDuration or the first propose");
       require(_votingParm.proposalSender != msg.sender,"proposal: can't propose twice in _voteDuration");
       require(_relpUserArray[_votingParm.proposalSender].rElpAmount < _relpUserArray[msg.sender].rElpAmount,
                                                                 "proposal: new  proposer must have move relp!");
       _votingParm.proposalK = detaK; 
       _votingParm.proposalSender = msg.sender;
       _votingParm.against = 0;
       _votingParm.approve = 0;
       _votingParm.turnout = 0;
       _votingParm.turnout += _relpUserArray[msg.sender].rElpAmount;
       _votingParm.approve += _relpUserArray[msg.sender].rElpAmount;
       _votingParm.bgProposalBlock = block.number;
       _voterMap[msg.sender].vote = true;
       _voterMap[msg.sender].blockNo =  block.number;
       return true;
    }
    // get the first proposal 
    function getProposalTaget() external view returns(uint256){
        if(_votingParm.proposalSender != address(0)){
            return _votingParm.proposalK;
        }
        return 0;
    }
    // vote  approve
    function approveVote() external returns (bool){
        require(_votingParm.proposalK > 0,"approveVote:proposalK first element must > 0 ");
        require(_votingParm.bgProposalBlock > 0 && block.number.sub(_votingParm.bgProposalBlock) > _voteDuration 
                 && block.number.sub(_votingParm.bgProposalBlock) < _voteDuration.mul(2));
        if( _voterMap[msg.sender].vote == true  && block.number.sub(_voterMap[msg.sender].blockNo) < _voteDuration){
            return false; 
        }
        _votingParm.turnout += _relpUserArray[msg.sender].rElpAmount;
        _votingParm.approve += _relpUserArray[msg.sender].rElpAmount;
        _voterMap[msg.sender].vote = true;
        _voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // withdraw proposal 
    function withdrawProposal() external returns (bool) {
        require(_votingParm.proposalK > 0,"withdrawProposal:proposalK element must > 0");
        require( _votingParm.proposalSender == msg.sender ,"withdrawProposal: msg.sender must the proposaler");
        if(block.number.sub(_votingParm.bgProposalBlock) > _voteDuration){
            return false;
        }
        _votingParm.bgProposalBlock = 0;
        _votingParm.proposalSender= address(0);
        _votingParm.proposalK = 0;
        _votingParm.against = 0;
        _votingParm.approve = 0;
        _votingParm.turnout = 0;
        return true;
    }
    // vote against
    function againstVote() external returns (bool){
        require(_votingParm.proposalK > 0,"approveVote:proposalK must > 0 ");
        require(_votingParm.bgProposalBlock > 0 && block.number.sub(_votingParm.bgProposalBlock)  > _voteDuration 
                || block.number.sub(_votingParm.bgProposalBlock) < _voteDuration.mul(2));
        if( _voterMap[msg.sender].vote == true  && block.number.sub(_voterMap[msg.sender].blockNo) < _voteDuration){
            return false; 
        }
        _votingParm.turnout += _relpUserArray[msg.sender].rElpAmount;
        _votingParm.against += _relpUserArray[msg.sender].rElpAmount;
        _voterMap[msg.sender].vote = true;
        _voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // get vote result
    function votingResult() public returns (bool){
      // no propsal
      if(_votingParm.proposalK == 0){
          return false;
      }
      // wait for voting
      if(_votingParm.bgProposalBlock > 0 &&  block.number.sub(_votingParm.bgProposalBlock) < _voteDuration.mul(2)){
          return false;
      }
      // compute result 
      bool votingRet = false;
      if(_votingParm.turnout == 0){
          return votingRet;
      }
      uint256 electorate = rElp.totalSupply();    
      uint256 agreeVotes = _votingParm.approve.div(Babylonian.sqrt(electorate));
      uint256 disagreeVotes = _votingParm.against.div(Babylonian.sqrt(_votingParm.turnout)); 
      if(agreeVotes > disagreeVotes){
           _elcAimParm.k =  _votingParm.proposalK; 
           votingRet = true;
       }
       _votingParm.bgProposalBlock = 0;
       _votingParm.proposalSender= address(0);
       _votingParm.proposalK = 0;
       _votingParm.against = 0;
       _votingParm.approve = 0;
       _votingParm.turnout = 0;
       return votingRet;
    }
    //check if msg.sender voted in _voteDuration
    function checkHasVote() external view returns (bool){
      if(_votingParm.bgProposalBlock == 0 || block.number.sub(_votingParm.bgProposalBlock) > _voteDuration.mul(2)){
           return false;
      }  
      return _voterMap[msg.sender].vote;
    }
    // get the approve votes amounts
    function getApproveTotal()external view returns(uint256){
        return _votingParm.approve;
    }
    // get the against votes amounts
    function getAgainstTotal()external view returns(uint256){
        return _votingParm.against;
    }
    //check if msg.sender just an proposer in  _voteDuration
    function checkProposaler(address proposaler) public view returns (bool){
      if(_votingParm.bgProposalBlock == 0 || block.number.sub(_votingParm.bgProposalBlock) > _voteDuration.mul(2)){
           return false;
      }  
      return (_votingParm.proposalSender == proposaler);
    }
}
