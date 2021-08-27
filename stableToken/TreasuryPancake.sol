// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.5;
import "./utils/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Babylonian.sol"; 
import "./libraries/TransferHelper.sol"; 
import {IOracle} from './OraclePancake.sol';
import {PancakeLibrary} from './libraries/PancakeLibrary.sol';
import {IPancakePair} from './interfaces/IPancakePair.sol';

import "./libraries/UniswapV2LiquidityMathLibrary.sol";
import {Epoch} from './utils/Epoch.sol';

contract Treasury is Ownable {
    using SafeMath for uint256;
    // used token contracts
    IERC20 internal elp;
    IERC20 internal elc;
    IERC20 internal rElp;
    IERC20 internal usdt;

    // oracle contract
    address internal elcOracle;
    address internal elpOracle;  

    // swap, for ELC/USDT pair
    IPancakePair internal elcSwap;
    // swap, for ELP/USDT pair
    IPancakePair internal elpSwap;
    
    // global Reserve variables
    struct globalReserveElement{
        uint256   elpReserveAmount;  // user add to the sys elp total amount
        uint256   elpRiskReserve;   // elp risk reserve
        uint256   elcRiskReserve;   // elc risk reserve 
        uint256   elpRewardAmount; // reward elp amount ,you need add it while used out
    }
    globalReserveElement private reserveGlobal;

    struct elcAimElement{ 
        uint256  elcAim ; // ELCaim price, decimal  
        uint256  k ;   // Anti-Inflation Factor 0.00005 
        uint256  elcaimLastBlock ;        // blockNum that elcaim last changed
    }
    elcAimElement private elcAimParm;
    
    // test  for 1%， Shrink by 100
    //uint256 constant private durationBlock = 200; // elcAim change duration
    //uint256 constant private adjustGap = 288;   // a day blocks total amounts
    //uint256 constant private voteDuration = 2016;   // vote duration
    //uint256 constant private voteBaserelpAmount = 1; // vote user base relp amount msust larger than this 
    //uint256 constant private elpRewardTotal = (20000 * 1e18);
    //uint256 constant private elpRewardFirstDay = (200 * 1e18);
    // test 
   
    // consant parms
     uint256 constant private durationBlock = 20000;  // elcAim change duration
     uint256 constant private adjustGap = 28800;      // a day blocks total amounts
     uint256 constant private voteDuration = 201600;  // vote duration
     uint256 constant private voteBaserelpAmount = 100; // vote user base relp amount msust larger than this 
     uint256 constant private elpRewardTotal = (2000000 * 1e18);
     uint256 constant private elpRewardFirstDay = (20000 * 1e18);
    
    // expand record of this system
    struct expandRec
    {
      uint256 totalCoinDay;
      uint256 expandBlockNo;
      uint256 totalExpandElc;
    }
    expandRec[] private  expandHisRec;
    // reward rate sturct 
    struct rewardRate{
        uint256  elpRewardRatePerBlock;
        uint256  elpRewardRateChgBlock;
    }
    rewardRate private rewardParm;

    struct userInfo{
        uint256   lastTimeExpandRewordforUser;  // The last time for  user to  allocate the rewards during the expansion
        uint256   rElpAmount;   // relp amount maparray that user put in pool
        uint256   rElpBlockCoinDay;// uRelp  coin*day 
        uint256   elpRewards; // elp stake rewords
        uint256   elpRewardPerCoinPaid; // elp stake rewords per coin 
        uint256   elcAmount;  // elc amount maparray that user put in pool  
        uint256   rElpLastUpdateTime;  // the last time relp amount change  
    }
    mapping (address => userInfo) private relpUserArray;
 
    struct rElpTotalAmountInfo
    {
        uint256  rElpPoolTotal;  // total rELP  in bankPool
        uint256  rElpCoinDayTotal;   // total rElpCoinDay  in bankPool
        uint256  relpTotalLastUpdateTime;  // last total relp change time 
    }
    rElpTotalAmountInfo  private  rElpTotalParm;
  
    // system accumulative reward per relp hold-time
    uint256 private rewardElpPerCoinStored = 0;    
    // last change status block
    uint256 private lastExpandTime = 0;
    // last change status block
    uint256 private lastContractTime = 0;
  
    // voting parameters
    struct votingElement{      
        uint256  against ;  // against votes amount
        uint256  approve ;  // approve votes amount
        uint256  turnout ;  // total votes amount
        uint256  bgProposalBlock ; // start proposal time     
        uint256  proposalK;  // proposal k target     
        address  proposalSender;   // proposal sender 
    }
    votingElement private votingParm;
    
    // voter info
    struct voteInfo{
        bool vote;      //  voted or not
        uint256 blockNo; // voting time
    }
    // voter Map 
    mapping(address => voteInfo) private voterMap;
   
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
       if((block.number).sub(elcAimParm.elcaimLastBlock) >= durationBlock){
           elcAimParm.elcAim =  caculateElcAim();
           elcAimParm.elcaimLastBlock = block.number;
       }
      _;
    }
    // Determine if elc price exceeds1.02
    modifier elcPriceOverUplimit(){
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256 _elcUpLimit = elcAimParm.elcAim.mul(102).div(100);
        require(_elcPrice > _elcUpLimit,"elcPrice must great than upLimits");
     _;
    }
    // Determine if elc price overdown 0.98  
    modifier elcPriceOverDownlimit(){
         uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256 _elcDownLimit = elcAimParm.elcAim.mul(98).div(100);
        require(_elcPrice < _elcDownLimit,"elcPrice must small than downLimits");
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
        rewardElpPerCoinStored = getElpRewardPerCoin();
        uint256 _rewardTmp = rewardELP();
        // must prepare enough elp amounts for staker rewards,
        if(reserveGlobal.elpRewardAmount >= _rewardTmp){
            relpUserArray[msg.sender].elpRewards += _rewardTmp; 
            reserveGlobal.elpRewardAmount -= _rewardTmp;
          }        
          relpUserArray[msg.sender].elpRewardPerCoinPaid = rewardElpPerCoinStored;
          rewardParm.elpRewardRatePerBlock = caculateRate( block.number); 
          rewardParm.elpRewardRateChgBlock = block.number;
        _;
    }
    // if elc expanded,get the els amounts to personal amout array
    modifier getExpandElc(){
        (uint256 _expandElcAmount,  uint256 _CoinDay, uint256 _UpdateTime ,  
                                         uint256 _LastTimeExpand) =  computeExpandElcBelongMe();
         relpUserArray[msg.sender].rElpLastUpdateTime = _UpdateTime;
         relpUserArray[msg.sender].lastTimeExpandRewordforUser = _LastTimeExpand;
         relpUserArray[msg.sender].rElpBlockCoinDay = _CoinDay;
        relpUserArray[msg.sender].elcAmount += _expandElcAmount;
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
        elp = IERC20(elpContract);
        elc = IERC20(elcContract);
        rElp = IERC20(relpContract);
        usdt = IERC20(usdtToken);
    
        lastContractTime = block.number;
        lastExpandTime = block.number;
       
        rElpTotalParm.relpTotalLastUpdateTime = block.number;
        rElpTotalParm.rElpPoolTotal = 0;      // total rELP  in bankPool
        rElpTotalParm.rElpCoinDayTotal = 0;   // total rElpCoinDay  in bankPool
       
        reserveGlobal.elpReserveAmount = 0;
        reserveGlobal.elpRiskReserve  = 0;
        reserveGlobal.elcRiskReserve = 0;
        reserveGlobal.elpRewardAmount = 0;
       
        votingParm.against = 0;  // against votes amount
        votingParm.approve = 0;  // approve votes amount
        votingParm.turnout = 0 ;  // total votes amount
        votingParm.bgProposalBlock = 0 ; // start proposal time     
        votingParm.proposalK = 0;  // proposal k target     
        votingParm.proposalSender = address(0);   // proposal sender 
      
        elcAimParm.elcAim = 1 * 1e18; // ELCaim price, decimal  
        elcAimParm.k = 5;   // Anti-Inflation Factor 0.00005 
        elcAimParm.elcaimLastBlock = block.number;

        rewardParm.elpRewardRatePerBlock =  elpRewardFirstDay.div(adjustGap);
        rewardParm.elpRewardRateChgBlock = block.number;
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
        elcSwap = IPancakePair(elcUsdtPair);
        elpSwap = IPancakePair(elpUsdtPair);
        elcOracle = elcOracleAddr;
        elpOracle = elpOracleAddr;
    }
    // add ELP liquidity，for Risk Reserve 
    function addRiskReserveElp(uint256 _elpAmount) external onlyOwner returns(bool _ret){
        require(_elpAmount > 0, "elp amount must > 0");
        _ret = addElp( _elpAmount);
        require(_ret == true, "addRiskReserveElp:transferFrom msgSender to this must succ");
        reserveGlobal.elpRiskReserve =  reserveGlobal.elpRiskReserve.add(_elpAmount);
        emit AddRiskELP(msg.sender, _elpAmount); 
    }
    // add ELP liquidity，for Rewards 
    function addRewardsElp(uint256 _elpAmount) external onlyOwner  returns(bool _ret){
        require(_elpAmount > 0, "elp amount must > 0");
        require(reserveGlobal.elpRewardAmount.add(_elpAmount) < elpRewardTotal, "reward elp amount must < totalreward");
        _ret = addElp( _elpAmount);
        require(_ret == true,"addRewardsElp:transferFrom msg.sender to this  must succ");
        reserveGlobal.elpRewardAmount= reserveGlobal.elpRewardAmount.add(_elpAmount);
        emit AddRewardsELP(msg.sender, _elpAmount); 
    }
    // add ELP liquidity to system
    function addElp(uint256 _elpAmount) internal  returns(bool _ret){
        require(_elpAmount > 0, "elp amount must > 0");
         _ret = elp.transferFrom(msg.sender, address(this), _elpAmount);
        require(_ret == true,"addReserveElp:transferFrom msg.sender to this  must succ");
        reserveGlobal.elpReserveAmount =  reserveGlobal.elpReserveAmount.add(_elpAmount); 
        emit AddReserveELP(msg.sender, _elpAmount);
    }
    // get total reward amount 
    function getTotalRewardsElpAmount() external  view returns(uint256){
        return reserveGlobal.elpRewardAmount;
    }
    // add ELP liquidity，returns rELP amount and ELC amount
    function addReserveElp(uint256 _elpAmount) external updatePrice updateRewardELP getExpandElc  returns(uint256  , uint256 ) {
        require(_elpAmount > 0, "elp amount must > 0");
        (uint256 _relpAmount,uint256 _elcAmount) = computeRelpElcbyAddELP(_elpAmount);
        if (_relpAmount == 0) {
            return (0, 0); 
        }
        bool _ret ;
        if (_elcAmount > 0) {
           _ret = elc.mint(msg.sender, _elcAmount);
           require(_ret  == true, "addElp:elc.mint must return true");
        }
        
        _ret = rElp.mint(address(this), _relpAmount);
        require(_ret  == true, "addElp:rElp.mint must return true");
        // new relp user
        if(relpUserArray[msg.sender].rElpAmount == 0){
             relpUserArray[msg.sender].lastTimeExpandRewordforUser =  block.number;
        }
        
        // compute new coinday should add 
        uint256 _newCoinDay = relpUserArray[msg.sender].rElpAmount.mul( (block.number
                             .sub(relpUserArray[msg.sender].rElpLastUpdateTime)).div(adjustGap) ) ;
        relpUserArray[msg.sender].rElpBlockCoinDay = relpUserArray[msg.sender].rElpBlockCoinDay.add( _newCoinDay );
        rElpTotalParm.rElpCoinDayTotal += _newCoinDay;

        relpUserArray[msg.sender].rElpAmount = relpUserArray[msg.sender].rElpAmount.add(_relpAmount);
        relpUserArray[msg.sender].rElpLastUpdateTime =  block.number;
        rElpTotalParm.rElpPoolTotal += _relpAmount;
        rElpTotalParm.relpTotalLastUpdateTime =  block.number;
         
        _ret = addElp(_elpAmount);
        require(_ret == true, "addElp: addReserveElp must succ"); 
        emit AddELP(msg.sender, _elpAmount, _relpAmount, _elcAmount);
        return (_relpAmount, _elcAmount);
    }
    // withdraw elp，
    function withdrawElp(uint256 _elpAmount) external updateRewardELP getExpandElc updatePrice lrLess90  returns(bool) {
        require(_elpAmount > 0, 'WithdrawElp: elpAmount must > 0 ');
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        bool _ret = false;
        if(_elpAmount < relpUserArray[msg.sender].elpRewards)
        {
            relpUserArray[msg.sender].elpRewards =  relpUserArray[msg.sender].elpRewards.sub(_elpAmount);
            _ret = elp.transfer(msg.sender, _elpAmount);
            require(_ret == true,"withdrawElp:elp.transfer must succ !");
            return _ret;
        }
        uint256 _tmpElpNeed = _elpAmount.sub(relpUserArray[msg.sender].elpRewards);
        (uint256 _relpNeed ,uint256 _elcNeed) = computeRelpElcbyWithdrawELP(_tmpElpNeed);
        require(( elc.balanceOf(msg.sender) >= _elcNeed)  && (relpUserArray[msg.sender].rElpAmount  >= _relpNeed),
                  "withdrawElp:must have enough elc and relp!");
              
        elc.burnFrom(msg.sender, _elcNeed);
        rElp.burn(_relpNeed);
        // compute new coinday should add 
        uint256 _newCoinDay = relpUserArray[msg.sender].rElpAmount
                            .mul( (block.number.sub(relpUserArray[msg.sender].rElpLastUpdateTime) ).div(adjustGap) ) ;
        if(relpUserArray[msg.sender].rElpAmount == _relpNeed)
        {
             relpUserArray[msg.sender].rElpBlockCoinDay = 0;
        }else{
              relpUserArray[msg.sender].rElpBlockCoinDay = relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( _newCoinDay );
        }
        if( rElpTotalParm.rElpPoolTotal == _relpNeed)
        {
             rElpTotalParm.rElpCoinDayTotal = 0;
        }else{
            rElpTotalParm.rElpCoinDayTotal += _newCoinDay; 
        } 
        relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        relpUserArray[msg.sender].rElpAmount = relpUserArray[msg.sender].rElpAmount.sub(_relpNeed);
        relpUserArray[msg.sender].elpRewards = 0;
        
        rElpTotalParm.rElpPoolTotal = rElpTotalParm.rElpPoolTotal.sub(_relpNeed);
        rElpTotalParm.relpTotalLastUpdateTime =  block.number;
        
        _ret = elp.transfer(msg.sender, _elpAmount);
        require(_ret == true,"withdrawElp:elp.transfer must succ !");
        reserveGlobal.elpReserveAmount =  reserveGlobal.elpReserveAmount.sub(_tmpElpNeed); 
        emit withdrawElpevent(msg.sender,_elpAmount); 
        return _ret;
    }
    // withdraw elc
    function withdrawElc(uint256 _elcAmount) external  returns(bool){
        require(_elcAmount <= relpUserArray[msg.sender].elcAmount,"withdrawElc:elcAmount <= relpUserArray[msg.sender].elcAmount");
        relpUserArray[msg.sender].elcAmount = relpUserArray[msg.sender].elcAmount.sub(_elcAmount); 
        bool _ret = elc.transfer(msg.sender, _elcAmount);
        require(_ret == true ,"withdrawElc:trasfer from this to user msust succ");
        emit withdrawELCevent(msg.sender, _elcAmount); 
        return _ret;
    }
    // user withdraw rELP and send it to user address
    function withdrawRELP(uint256 _relpAmount)  external updateRewardELP getExpandElc returns(bool){
        require(_relpAmount <= relpUserArray[msg.sender].rElpAmount,"withdrawRELP:withdraw amount must < rElpAmount hold!");
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        // compute new coinday should add 
        uint256 _newCoinDay = relpUserArray[msg.sender].rElpAmount
                           .mul( (block.number.sub(relpUserArray[msg.sender].rElpLastUpdateTime) ).div(adjustGap) ) ;
        if(relpUserArray[msg.sender].rElpAmount == _relpAmount)
        {
             relpUserArray[msg.sender].rElpBlockCoinDay = 0;
        }else{
             relpUserArray[msg.sender].rElpBlockCoinDay = relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( _newCoinDay );
        }
        if( rElpTotalParm.rElpPoolTotal == _relpAmount)
        {
             rElpTotalParm.rElpCoinDayTotal = 0;
        }else{
            rElpTotalParm.rElpCoinDayTotal += _newCoinDay; 
        }
       
        relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        relpUserArray[msg.sender].rElpAmount =  relpUserArray[msg.sender].rElpAmount.sub(_relpAmount);
        
        rElpTotalParm.rElpPoolTotal = rElpTotalParm.rElpPoolTotal.sub(_relpAmount);
        rElpTotalParm.relpTotalLastUpdateTime =  block.number;
       
        bool _ret = rElp.transfer(msg.sender, _relpAmount);
        require(_ret == true,"withdrawRELP:rElp.transfer must succ");
        emit withdrawRelpevent(msg.sender, _relpAmount); 
        return _ret;
    }
    // user add rELP to pool, liquidity miner
    function addRELP(uint256 _relpAmount) external updateRewardELP getExpandElc returns(bool ){
        require(_relpAmount > 0,"addRELP:relpAmount >0 ");
        // compute new coinday shuld add 
        uint256 _newCoinDay = relpUserArray[msg.sender].rElpAmount
                          .mul( (block.number.sub(relpUserArray[msg.sender].rElpLastUpdateTime) ).div(adjustGap) ) ;
        relpUserArray[msg.sender].rElpBlockCoinDay = relpUserArray[msg.sender].rElpBlockCoinDay
                  .add( _newCoinDay );
        rElpTotalParm.rElpCoinDayTotal += _newCoinDay;
        relpUserArray[msg.sender].rElpAmount = relpUserArray[msg.sender].rElpAmount.add(_relpAmount);
        relpUserArray[msg.sender].rElpLastUpdateTime = block.number;
        rElpTotalParm.rElpPoolTotal += _relpAmount;
        rElpTotalParm.relpTotalLastUpdateTime =  block.number;
        bool _ret = rElp.transferFrom(msg.sender, address(this), _relpAmount);
        require(_ret == true,"addRELP:rElp.transfer to this must succ");
        emit AddRelpEvent(msg.sender, _relpAmount); 
        return _ret;
    }
    // update oracle token price
    function updateCashPrice() internal {
        if (Epoch(elcOracle).callable()) {
            try IOracle(elcOracle).update() {} catch {}
        }       
        if (Epoch(elpOracle).callable()) {
            try IOracle(elpOracle).update() {} catch {}
        }
    }
    // swap token, for expansion and contraction
    function swapToken(bool _elcBuyElpTag, uint256 _amountIn) public returns (uint256){
        require( _amountIn > 0);
        address[] memory _path1 = new address[](3);
        uint256[] memory _amounts = new uint256[](_path1.length);
        if(_elcBuyElpTag)
        {
            _path1[0] = address(elc);
            _path1[1] = address(usdt);
            _path1[2] = address(elp);
            _amounts = PancakeLibrary.getAmountsOut(elcSwap.factory(),_amountIn, _path1);
            TransferHelper.safeTransfer(address(elc),address(elcSwap),_amountIn);    
        }else{
            _path1[0] = address(elp);
            _path1[1] = address(usdt);
            _path1[2] = address(elc);
            _amounts = PancakeLibrary.getAmountsOut(elpSwap.factory(),_amountIn, _path1);
            TransferHelper.safeTransfer(address(elp),address(elpSwap),_amountIn); 
        }    
        for (uint256 i = 0; i < _path1.length - 1; i++) {
            (address _input, address _output) = (_path1[i], _path1[i + 1]);
            (address _token0, ) = PancakeLibrary.sortTokens(_input, _output);
            uint256 _amountOut = _amounts[i + 1];
            (uint256 _amount0Out, uint256 _amount1Out) = _input == _token0
                    ? (uint256(0), _amountOut)
                    : (_amountOut, uint256(0));
            address _to = i < _path1.length - 2 ? PancakeLibrary.pairFor(elcSwap.factory(), _output, _path1[i + 2]) : address(this);
           
            IPancakePair(PancakeLibrary.pairFor(elcSwap.factory(), _input, _output)).swap(_amount0Out, _amount1Out, _to, "");
        }
        return _amounts[_amounts.length -1];
    }
    // compute elc amount belong to msg.sender while expand
    function computeExpandElcBelongMe() internal view returns(uint256, uint256 ,uint256, uint256){
        uint256 _tempLastUpdateTime = relpUserArray[msg.sender].rElpLastUpdateTime;
        uint256 _tempBlockCoinDay = relpUserArray[msg.sender].rElpBlockCoinDay;
        uint256 _tempLastTimeExpandRewordforUser = relpUserArray[msg.sender].lastTimeExpandRewordforUser;
        uint256 _expandElcAmount= 0;
        for(uint256 i = 0; i < expandHisRec.length; i++)
        {
            uint _caculateTime = expandHisRec[i].expandBlockNo;
            if( _tempLastTimeExpandRewordforUser >= _caculateTime )
            {
               continue;
            }
            _tempBlockCoinDay  +=  relpUserArray[msg.sender].rElpAmount.mul( ( _caculateTime.sub(_tempLastUpdateTime) ).div(adjustGap) );
            _expandElcAmount += FullMath.mulDiv(_tempBlockCoinDay, expandHisRec[i].totalExpandElc, expandHisRec[i].totalCoinDay);
            _tempBlockCoinDay = 0;
            _tempLastUpdateTime = _caculateTime;
            _tempLastTimeExpandRewordforUser = _caculateTime;
        }
        return ( _expandElcAmount, _tempBlockCoinDay, _tempLastUpdateTime , _tempLastTimeExpandRewordforUser);
    }
    
    // expand cycle. raise ELC, swap ELC to ELP
    function expansion() external updatePrice updateElcAim lrLess70 elcPriceOverUplimit expandInOneDayAg  returns(uint256) {
        lastExpandTime = block.number;
        uint256 _elcSellAmount = expansionComputeElc();
        uint256 _elpAmount = 0;
        if( reserveGlobal.elcRiskReserve >= _elcSellAmount) {
             reserveGlobal.elcRiskReserve =  reserveGlobal.elcRiskReserve.sub(_elcSellAmount);
            _elpAmount = swapToken(true,_elcSellAmount);
            reserveGlobal.elpRiskReserve += _elpAmount;
        } else {
           uint256 _mintAmount = 0;
           uint256 _temp =  reserveGlobal.elcRiskReserve;
           if( reserveGlobal.elcRiskReserve > 0){
               reserveGlobal.elcRiskReserve = 0;
               _elpAmount = swapToken(true,_temp);
               reserveGlobal.elpRiskReserve += _elpAmount;
               _mintAmount = _elcSellAmount.sub(_temp);
           } else  if( reserveGlobal.elcRiskReserve == 0){
               _mintAmount = _elcSellAmount;
           }
           require(elc.mint(address(this), _mintAmount),"expansion:elc.mint fun must succ!");
           _elpAmount = swapToken(true,_mintAmount.mul(5).div(100));
           reserveGlobal.elpRiskReserve += _elpAmount;
           rElpTotalParm.rElpCoinDayTotal += rElpTotalParm.rElpPoolTotal
                          .mul(  ( (block.number).sub(rElpTotalParm.relpTotalLastUpdateTime) ).div(adjustGap) );          
           uint256  _expandElcforRelp = FullMath.mulDiv(_mintAmount,95,100);
           expandHisRec.push(expandRec(rElpTotalParm.rElpCoinDayTotal,block.number,_expandElcforRelp));
           rElpTotalParm.rElpCoinDayTotal = 0;
           rElpTotalParm.relpTotalLastUpdateTime = block.number;
        }
        emit ExpandCycle(block.number, _elcSellAmount);
        return _elcSellAmount;
    }
    // contract cycle. swap ELP to ELC
    function contraction() external updatePrice elcPriceOverDownlimit contractInOneDayAg  updateElcAim  returns(uint256) {
        uint256 _elcAmount = 0;
        uint256 _elpNeedSell = contractionComputeElpNeed();
        lastContractTime = block.number;
        if (_elpNeedSell <=  reserveGlobal.elpRiskReserve) {
            reserveGlobal.elpRiskReserve -= _elpNeedSell;
            _elcAmount = swapToken(false,_elpNeedSell);
            reserveGlobal.elcRiskReserve += _elcAmount;
        } else {
            uint256 _elp2percent =  reserveGlobal.elpReserveAmount.mul(2).div(100);
            if(_elpNeedSell < reserveGlobal.elpRiskReserve.add(_elp2percent)) {
                 reserveGlobal.elpReserveAmount =  reserveGlobal.elpRiskReserve.add( reserveGlobal.elpReserveAmount).sub(_elpNeedSell);
                 reserveGlobal.elpRiskReserve = 0;
                 _elcAmount = swapToken(false,_elpNeedSell);
                 reserveGlobal.elcRiskReserve += _elcAmount; 
            } else {
                _elpNeedSell = reserveGlobal.elpRiskReserve.add(_elp2percent);
                reserveGlobal.elpRiskReserve = 0;
                reserveGlobal.elpReserveAmount -= _elp2percent;
                _elcAmount = swapToken(false,_elpNeedSell);
                reserveGlobal.elcRiskReserve += _elcAmount;
            }
        }
       emit ContractCycle(block.number, _elpNeedSell);
       return _elpNeedSell; 
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    // get the amount of elc belone to msg.sender
    function getElcAmount() external view returns (uint256){
        return relpUserArray[msg.sender].elcAmount;
    }
    // get the msg.sender's relp amounts
    function getRelpAmount() external view returns (uint256){
       return relpUserArray[msg.sender].rElpAmount;
    }
    // for debugging use ,getblance of this contract's relp
    function getRElpPoolTotalAmount() external view onlyOwner returns (uint256){
       return rElpTotalParm.rElpPoolTotal;
    }
    // for debugging use ,getblance of this contract's elp
    function getElpPoolTotalAmount() external view onlyOwner returns (uint256){
       return (reserveGlobal.elpReserveAmount + reserveGlobal.elpRiskReserve + reserveGlobal.elpRewardAmount);
    }
    // for debugging use ,getblance of this contract's elc
    function getElcPoolTotalAmount() external view onlyOwner returns (uint256){
       return elc.balanceOf(address(this));
    }
    // compute the ELP amount get rELP amount and ELC amount
    function computeRelpElcbyAddELP(uint256  _elpAmount) internal view returns(uint256 , uint256 ) {
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256  _elpPrice  = getOraclePrice(elpOracle,address(elp));
        uint256 _relpAmount = 0;
        uint256 _elcAmount = 0;
        uint256  _lr = liabilityRatio();
        if (_lr <= 30) {
           uint256   _relpPrice = computeRelpPrice();
           _relpAmount =  FullMath.mulDiv( _elpAmount,_elpPrice.mul(100 - _lr),_relpPrice.mul(100) );
           _elcAmount =  FullMath.mulDiv( _elpAmount,_elpPrice.mul(_lr),_elcPrice.mul(100) );
        } else if (_lr <= 90 && _lr > 30){
            uint256   _relpPrice = computeRelpPrice();
            _relpAmount =  FullMath.mulDiv( _elpAmount,_elpPrice,_relpPrice);
            _elcAmount  = 0; 
        } else if (_lr > 90){
            uint256  _relpPrice90 = computeRelpPrice90();
            _relpAmount =  FullMath.mulDiv( _elpAmount,_elpPrice,_relpPrice90);
            _elcAmount  = 0; 
        }
        return ( _relpAmount,  _elcAmount);
    }
    // caculate elc and relp amount while withdraw elp
    function computeRelpElcbyWithdrawELP(uint256  _elpAmount) internal view returns(uint256 , uint256 ){
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256  _elpPrice  = getOraclePrice(elpOracle,address(elp));
        uint256 _relpAmount =0;
        uint256 _elcAmount = 0;
        uint256  _lr = liabilityRatio();
        uint256   _relpPrice = computeRelpPrice();  
        if(_lr < 90){
           _relpAmount =  FullMath.mulDiv( _elpPrice,_elpAmount.mul(100 - _lr),_relpPrice.mul(100) );
           _elcAmount =  FullMath.mulDiv( _elpPrice,_elpAmount.mul(_lr),_elcPrice.mul(100) );  
        }
        return (_relpAmount,_elcAmount);
    }
    // get the aimPrice at nearst blocktime
    function getAimPrice() public view returns(uint256){
       uint256 _tempElcAim = elcAimParm.elcAim; 
       if((block.number).sub(elcAimParm.elcaimLastBlock) >= durationBlock){
           _tempElcAim =  caculateElcAim();
       }
       return _tempElcAim;
    }
    // compute the selling elp amount, the buying elc amounts the betwixt usdt amount while contraction
    function contractionComputeElpNeed() internal view returns(uint256) {      
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        require(_elcPrice < elcAimParm.elcAim.mul(98).div(100),"contractionComputeElpAndElc: true price less than aim");
        (uint256 _reserve0, uint256 _reserve1,) = elcSwap.getReserves();
        uint256 _reserveUSDT = 0;
        uint256 _reserveELC = 0;
        (address _token0, ) = PancakeLibrary.sortTokens(address(elc), address(usdt));
        if(_token0 == address(elc)){
            _reserveELC = _reserve0;
            _reserveUSDT = _reserve1;
        }else{
            _reserveUSDT = _reserve0;
            _reserveELC = _reserve1;
        }         
        (bool _usdtToELC, uint256 _usdtNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
                1E18, elcAimParm.elcAim.mul(98).div(100),_reserveUSDT, _reserveELC);
        if (_usdtNeed == 0 || _usdtToELC == false) {
            return 0;
        }
        uint256 _reserveELP = 0;
        uint256 _reserveUSDT2 = 0;
        (_reserve0, _reserve1, ) = elpSwap.getReserves();
        (_token0, ) = PancakeLibrary.sortTokens(address(elp), address(usdt));
        if(_token0 == address(elp)){
            _reserveELP = _reserve0;
            _reserveUSDT2 = _reserve1;
        }else{
            _reserveUSDT2 = _reserve0;
            _reserveELP = _reserve1;
        }        
        if(_usdtNeed > _reserveUSDT2){
              return 0;
        }       
        return PancakeLibrary.getAmountIn(_usdtNeed, _reserveELP, _reserveUSDT2);
    }
    // compute the selling elc amount, the buying elp amounts the betwixt usdt amount while expansion
    function expansionComputeElc() internal view returns(uint256) {
       uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
       require(_elcPrice > elcAimParm.elcAim.mul(102).div(100),"contractionComputeElpAndElc: true price large than aim 102%");
        (uint256 _reserve0, uint256 _reserve1,) = elcSwap.getReserves();
        uint256 _reserveUSDT;
        uint256 _reserveELC;
        if(elcSwap.token0() == address(elc)){
            _reserveELC = _reserve0;
            _reserveUSDT = _reserve1;
        }else{
            _reserveUSDT = _reserve0;
            _reserveELC = _reserve1;
        }
        (bool _elcToUsdt, uint256 _elcNeed) = UniswapV2LiquidityMathLibrary.computeProfitMaximizingTrade(
               1E18, elcAimParm.elcAim, _reserveELC, _reserveUSDT);
         if(_elcToUsdt){
             return _elcNeed;
         }
         return 0;
    }
    // get reserve elp amount
    function getElpReserve() external view returns(uint256) {
        return  reserveGlobal.elpReserveAmount;
    }
    // get risk_reserve elp amount 
    function getElpRiskReserve() external view returns(uint256) {
        return  reserveGlobal.elpRiskReserve;
    }
    // get risk_reserve ELC
    function getElcRiskReserve() external view returns(uint256) {
        return  reserveGlobal.elcRiskReserve;
    }
    // get K factor
    function getK() external view returns(uint256) {
        return elcAimParm.k;
    }
    // compute rELP price
    function computeRelpPrice() internal view returns(uint256) {
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256  _elpPrice  = getOraclePrice(elpOracle,address(elp));
        uint256 _relpTotal = rElp.totalSupply();
        uint256 _elcTotal  = elc.totalSupply();
        if (_relpTotal == 0 || reserveGlobal.elpReserveAmount == 0){
             return 1E18;  
        }
        (uint256 _elpl, uint256 _elph) = FullMath.fullMul(reserveGlobal.elpReserveAmount, _elpPrice);
        (uint256 _elcl, uint256 _elch) =  FullMath.fullMul(_elcTotal, _elcPrice); 
        if((_elph > _elch) || ( (_elph == _elch) && (_elpl > _elcl) ) ){
            uint256 _relpPrice =  FullMath.mulDiv( reserveGlobal.elpReserveAmount,_elpPrice,_relpTotal );
            _relpPrice = _relpPrice.sub( FullMath.mulDiv( _elcTotal,_elcPrice,_relpTotal) );
            return _relpPrice;  
        }
        return 1E18; 
    }
    // lr = 90%  prelp
    function computeRelpPrice90() internal view returns(uint256){
       uint256  _elpPrice  = getOraclePrice(elpOracle,address(elp));
       uint256 _relpTotal = rElp.totalSupply();
       if (_relpTotal == 0 || reserveGlobal.elpReserveAmount == 0) {
           return   1E18; 
       }
       uint256 _relpPrice =  FullMath.mulDiv( reserveGlobal.elpReserveAmount,_elpPrice.mul(10),_relpTotal.mul(100) );
       return _relpPrice;
    }
    // liability Ratio
    function liabilityRatio() public view returns(uint256) {
        // not only initial, anytime reserve down to zero should protect.
        if ( reserveGlobal.elpReserveAmount == 0) {
            return 20;
        }
        uint256 _lr = 0;      
        uint256  _elcPrice = getOraclePrice(elcOracle,address(elc));
        uint256  _elpPrice  = getOraclePrice(elpOracle,address(elp));
        uint256 _elcTotal = elc.totalSupply();
        
        if(_elpPrice > 0 &&  reserveGlobal.elpReserveAmount > 0){
            _lr = ( FullMath.mulDiv(_elcTotal.mul(100), _elcPrice,_elpPrice) ).div( reserveGlobal.elpReserveAmount);
        }       
        if (_lr >= 100) {
            // up bound is 100
            return 100;
        }
        if (_lr == 0) {
            return 1;
        }
        return _lr;
    }
    // reward per token
    function getElpRewardPerCoin() internal view returns (uint256) {
        uint256 _tmpRatePerBlock = caculateAvgRatePerBlock(rElpTotalParm.relpTotalLastUpdateTime);
        if (rElpTotalParm.rElpPoolTotal == 0){
            return rewardElpPerCoinStored;
        }
       return rewardElpPerCoinStored.add(
                    (block.number - rElpTotalParm.relpTotalLastUpdateTime)
                    .mul(_tmpRatePerBlock)
                    .mul(1e18)
                    .div(rElpTotalParm.rElpPoolTotal));
    }
    // caculate true reward rate.
    function caculateAvgRatePerBlock(uint256 _updateTime) internal view returns(uint256){
      require(block.number >= _updateTime,"caculateAvgRatePerBlock: block.number must >= updateTime");
         uint256 _rate = caculateRate(_updateTime);
         uint256 _span = (block.number.sub(_updateTime)).div(adjustGap); 
         uint256 _avgRate = 0;
        if(_span == 0){
             return _rate;
        }
        uint256 _temp = 10;
        uint256 _aTemp = 0;
        uint256 _sTotal = 0;
        while(_span > 0){
            if(_span > _temp){
                _aTemp = _rate.mul(99**9).div( 100**9);
                _sTotal = _sTotal.add(_rate.mul(100).sub(_aTemp.mul(99)));
                _rate = _aTemp;
                _span = _span.sub(_temp); 
            }else{
                _aTemp = _rate.mul(99**(_span-1)).div( 100**(_span -1));
                _sTotal = _sTotal.add(_rate.mul(100).sub(_aTemp.mul(99)));
                _span = 0;
            }
        }
        _avgRate = (_sTotal.mul(adjustGap)).add( _aTemp.mul( block.number.mod(adjustGap)) );
        _avgRate = _avgRate.div(block.number.sub(_updateTime));
        return _avgRate;
    }  
    // caculate true reward rate.
    function caculateRate(uint256 _rateTime) internal view returns(uint256){
        require(_rateTime >= rewardParm.elpRewardRateChgBlock,"caculateRate: time > rateChgblock");
        uint256 _span = (_rateTime - rewardParm.elpRewardRateChgBlock).div(adjustGap);
        uint256 _rate = rewardParm.elpRewardRatePerBlock;
        uint256 _aTemp = _rate;
        uint256 _temp = 10;
        while(_span > 0){
            if(_span > _temp){
                _aTemp = _rate.mul(99**9).div( 100**9);
                _rate = _aTemp;
                _span = _span.sub(_temp); 
            }else{
                _aTemp = _rate.mul(99**(_span-1)).div( 100**(_span-1));
                _span = 0;
            }
        }
        return _aTemp;
    }
    // caculate rElp rewards
    function rewardELP() public view returns (uint256) {
        return relpUserArray[msg.sender].rElpAmount
                .mul(getElpRewardPerCoin().sub(relpUserArray[msg.sender].elpRewardPerCoinPaid))
                .div(1e18)
                .add(relpUserArray[msg.sender].elpRewards);
    }
    // caculate elc aim price
    function caculateElcAim() public view returns(uint256){
        uint256 _span = (block.number).sub(elcAimParm.elcaimLastBlock).div(durationBlock);
        uint256 _tempK = 1;
        uint256 _tempDiv = 1;
        uint256 _temp = 10;
        while(_span > 0){
           if(_span > _temp){
                _tempK = _tempK.mul( (100000 +elcAimParm.k)**9 );
                _tempDiv = _tempDiv.mul(100000 ** 9);
                _tempK = _tempK.div(_tempDiv);
                _tempDiv = 1;
                _span = _span.sub(_temp); 
            }else{
                _tempK = _tempK.mul( (100000 +elcAimParm.k)**(_span -1) );
                _tempDiv = _tempDiv.mul(100000 ** (_span -1));
                _span = 0;
            }
        }
        return elcAimParm.elcAim.mul(_tempK).div(_tempDiv);
    }
    
    /* ==========K VOTE FUNCTIONS ========== */
    // proposal k factor
    function proposal(uint256 _detaK) external returns (bool) {
       require(_detaK > 0,"proposal:detaK must > 0");
       require(relpUserArray[msg.sender].rElpAmount >= voteBaserelpAmount,"proposal:relp hold must > voteBaserelpAmount");
       require(votingParm.bgProposalBlock == 0 || (block.number - votingParm.bgProposalBlock) < voteDuration,
                                                                 "proposal:must in voteDuration or the first propose");
       require(votingParm.proposalSender != msg.sender,"proposal: can't propose twice in voteDuration");
       require(relpUserArray[votingParm.proposalSender].rElpAmount < relpUserArray[msg.sender].rElpAmount,
                                                                 "proposal: new  proposer must have move relp!");
       votingParm.proposalK = _detaK; 
       votingParm.proposalSender = msg.sender;
       votingParm.against = 0;
       votingParm.approve = 0;
       votingParm.turnout = 0;
       votingParm.turnout += relpUserArray[msg.sender].rElpAmount;
       votingParm.approve += relpUserArray[msg.sender].rElpAmount;
       votingParm.bgProposalBlock = block.number;
       voterMap[msg.sender].vote = true;
       voterMap[msg.sender].blockNo =  block.number;
       return true;
    }
    // get the first proposal 
    function getProposalTaget() external view returns(uint256){
        if(votingParm.proposalSender != address(0)){
            return votingParm.proposalK;
        }
        return 0;
    }
    // vote  approve
    function approveVote() external returns (bool){
        require(votingParm.proposalK > 0,"approveVote:proposalK first element must > 0 ");
        require(votingParm.bgProposalBlock > 0 && block.number.sub(votingParm.bgProposalBlock) > voteDuration 
                 && block.number.sub(votingParm.bgProposalBlock) < voteDuration.mul(2));
        if( voterMap[msg.sender].vote == true  && block.number.sub(voterMap[msg.sender].blockNo) < voteDuration){
            return false; 
        }
        votingParm.turnout += relpUserArray[msg.sender].rElpAmount;
        votingParm.approve += relpUserArray[msg.sender].rElpAmount;
        voterMap[msg.sender].vote = true;
        voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // withdraw proposal 
    function withdrawProposal() external returns (bool) {
        require(votingParm.proposalK > 0,"withdrawProposal:proposalK element must > 0");
        require( votingParm.proposalSender == msg.sender ,"withdrawProposal: msg.sender must the proposaler");
        if(block.number.sub(votingParm.bgProposalBlock) > voteDuration){
            return false;
        }
        votingParm.bgProposalBlock = 0;
        votingParm.proposalSender= address(0);
        votingParm.proposalK = 0;
        votingParm.against = 0;
        votingParm.approve = 0;
        votingParm.turnout = 0;
        return true;
    }
    // vote against
    function againstVote() external returns (bool){
        require(votingParm.proposalK > 0,"approveVote:proposalK must > 0 ");
        require(votingParm.bgProposalBlock > 0 && block.number.sub(votingParm.bgProposalBlock)  > voteDuration 
                || block.number.sub(votingParm.bgProposalBlock) < voteDuration.mul(2));
        if( voterMap[msg.sender].vote == true  && block.number.sub(voterMap[msg.sender].blockNo) < voteDuration){
            return false; 
        }
        votingParm.turnout += relpUserArray[msg.sender].rElpAmount;
        votingParm.against += relpUserArray[msg.sender].rElpAmount;
        voterMap[msg.sender].vote = true;
        voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // get vote result
    function votingResult() public returns (bool){
      // no propsal
      if(votingParm.proposalK == 0){
          return false;
      }
      // wait for voting
      if(votingParm.bgProposalBlock > 0 &&  block.number.sub(votingParm.bgProposalBlock) < voteDuration.mul(2)){
          return false;
      }
      // compute result 
      bool _votingRet = false;
      if(votingParm.turnout == 0){
          return _votingRet;
      }
      uint256 _electorate = rElp.totalSupply();    
      uint256 _agreeVotes = votingParm.approve.div(Babylonian.sqrt(_electorate));
      uint256 _disagreeVotes = votingParm.against.div(Babylonian.sqrt(votingParm.turnout)); 
      if(_agreeVotes > _disagreeVotes){
           elcAimParm.k =  votingParm.proposalK; 
           _votingRet = true;
       }
       votingParm.bgProposalBlock = 0;
       votingParm.proposalSender= address(0);
       votingParm.proposalK = 0;
       votingParm.against = 0;
       votingParm.approve = 0;
       votingParm.turnout = 0;
       return _votingRet;
    }
    //check if msg.sender voted in voteDuration
    function checkHasVote() external view returns (bool){
      if(votingParm.bgProposalBlock == 0 || block.number.sub(votingParm.bgProposalBlock) > voteDuration.mul(2)){
           return false;
      }  
      return voterMap[msg.sender].vote;
    }
    // get the approve votes amounts
    function getApproveTotal()external view returns(uint256){
        return votingParm.approve;
    }
    // get the against votes amounts
    function getAgainstTotal()external view returns(uint256){
        return votingParm.against;
    }
    //check if msg.sender just an proposer in  voteDuration
    function checkProposaler(address proposaler) public view returns (bool){
      if(votingParm.bgProposalBlock == 0 || block.number.sub(votingParm.bgProposalBlock) > voteDuration.mul(2)){
           return false;
      }  
      return (votingParm.proposalSender == proposaler);
    }
}
