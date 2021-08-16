// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0 <0.8.5;
import "./libraries/Ownable.sol";
import "./interfaces/IERC20.sol";
import "./libraries/Address.sol";
import "./libraries/SafeMath.sol";
import "./libraries/Babylonian.sol"; 
import "./libraries/TransferHelper.sol"; 
import {IOracle} from './Oracle.sol';
import {BakerySwapLibrary} from './libraries/BakerySwapLibrary.sol';
import {IBakerySwapPair} from './interfaces/IBakerySwapPair.sol';
import "./libraries/UniswapV2LiquidityMathLibrary.sol";

contract Treasury is Ownable {
    using SafeMath for uint256;
    // used contracts
    IERC20 internal elp;
    IERC20 internal elc;
    IERC20 internal rElp;
    IERC20 internal usdt;
    address internal elcOracle;
    address internal elpOracle;
    
    // swap, for ELC/USDT pair
    IBakerySwapPair internal elcSwap;
    // swap, for ELP/USDT pair
    IBakerySwapPair internal elpSwap;
    
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
    // elcaim renew blockno
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
    struct expandRec
    {
      uint256 totalCoinDay;
      uint256 expandBlockNo;
      uint256 totalExpandElc;
      uint256 elcPerCoinDay;
    }
    
    expandRec[] private  expandHisRec;
    
    // ELP block revenue rate
    uint256 constant private elpRewardTotal = (2000000 * 1e18);
    uint256 private elpRewardPool = 0;
    uint256  constant private elpRewardFirstDay = (20000 * 1e18);
    uint256  private elpRewardRatePerBlock =  elpRewardFirstDay.div(adjustGap);
   
    // relp amount maparray that user put in pool
    mapping (address => uint256) private getLastElcExpandTime;
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
     // total rElpCoinDayTotal  in bankPool
    uint256 private rElpCoinDayTotal = 0;
    // system accumulative reward per relp hold-time
    uint256 private rewardElpPerCoinStored = 0;    
    // last relp change time 
    uint256 private relpLastUpdateTime = 0;
    // elp stake rewords
    mapping(address => uint256) private elpRewards;
    // elp stake rewords per coin 
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
    // proposal k target 
    uint256 private proposalK; 
    // proposal sender 
    address private proposalSender;
    // voter info
    struct voteInfo{
        bool vote;
        uint256 blockNo;
    }
    // voter Map 
    mapping(address => voteInfo) private voterMap;
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
        uint256 elc_price = getELPOraclePrice();
        uint256 elc_up_limit = elcAim.mul(102).div(100);
        require(elc_price > elc_up_limit,"elcPrice must great than upLimits");
     _;
    }
    // Determine if elc price overdown 0.98  
    modifier elcPriceOverDownlimit(){
        uint256 elc_price = getELPOraclePrice();
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
        if(elpRewardPool >= rewardTmp)
        {  
            elpRewards[msg.sender] += rewardTmp; 
            elpRewardPool -= rewardTmp;
        }
        _;
    }
    // if elc expanded,get the els amounts to personal amout array
    modifier getExpandElc(){
        elcAmountArray[msg.sender] += computeExpandElcBelongMe();
        _;
    }
    // compute elc amount belong to msg.sender while expand
    function computeExpandElcBelongMe() public returns(uint256){
        uint256 temp = rElpBgBlockArray[msg.sender];
        uint256 expandElcAmount= 0;
        for(uint256 i = 0; i < expandHisRec.length; i++)
        {
            uint caculateTime = expandHisRec[i].expandBlockNo;
            if( getLastElcExpandTime[msg.sender] >=caculateTime )
            {
               continue;
            }
            
            if(caculateTime >= getLastElcExpandTime[msg.sender])
            {
               rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add( rElpAmountArray[msg.sender].mul(caculateTime.sub(temp).div(adjustGap)) );
               expandElcAmount +=  rElpBlockCoinDayArray[msg.sender].mul(expandHisRec[i].elcPerCoinDay);
               rElpBlockCoinDayArray[msg.sender] = 0;
               temp = caculateTime;
               getLastElcExpandTime[msg.sender] = caculateTime;
            }
        }
       return expandElcAmount;
    }
    
    constructor(address elpContract, 
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
    // get a day avarage price of elp 
    function getELPOraclePrice() public view returns (uint256) {
       try IOracle(elpOracle).consult(address(elp), 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert('Treasury: failed to consult elp price from the oracle');
        }
    }
    // get a day avarage price of elc 
    function getELCOraclePrice() public view returns (uint256) {
        try IOracle(elcOracle).consult(address(elc), 1e18) returns (uint256 price) {
            return price;
        } catch {
            revert('Treasury: failed to consult cash price from the oracle');
        }
    }
    // set swap address
    function setSwap(address elcUsdtPair, address elpUsdtPair, address elcOracleAddr,  address elpOracleAddr) external onlyOwner {
        elcSwap = IBakerySwapPair(elcUsdtPair);
        elpSwap = IBakerySwapPair(elpUsdtPair);
        elcOracle = elcOracleAddr;
        elpOracle = elpOracleAddr;
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
    function addElp(uint256 elpAmount) external updateRewardELP getExpandElc returns(uint256 , uint256) {
        require(elpAmount > 0, "elp amount must > 0");
        bool ret = addReserveElp(elpAmount);
        require(ret == true, "addElp: addReserveElp must succ");
       
        uint256 relpAmount = 0;
        uint256 elcAmount = 0;
        (relpAmount, elcAmount) = computeRelpElcbyAddELP(elpAmount);
        if (elcAmount > 0) {
           ret = elc.mint(address(this), elcAmount);
           require(ret  == true, "addElp:elc.mint must return true");
           elcAmountArray[msg.sender] += elcAmount;
        }
        if (relpAmount > 0) {
            if(rElpAmountArray[msg.sender] == 0)
            {
                 getLastElcExpandTime[msg.sender] =  block.number;
            }
            ret = rElp.mint(address(this), relpAmount);
            require(ret  == true, "addElp:rElp.mint must return true");
           
            if(rElpBgBlockArray[msg.sender] > 0)
            {
               rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add( rElpAmountArray[msg.sender].mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap)) );
            }else{
               rElpBlockCoinDayArray[msg.sender] = 0;
            }
            rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].add(relpAmount);
            rElpPoolTotal = rElpPoolTotal.add(relpAmount);
            rElpCoinDayTotal += rElpAmountArray[msg.sender].mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap));
            rElpBgBlockArray[msg.sender] = block.number;
        } 
      
        emit AddELP(msg.sender, elpAmount, relpAmount, elcAmount);
        return (relpAmount, elcAmount);
    }
    // withdraw elp，
    function withdrawElp(uint256 elpAmount) external updateRewardELP getExpandElc lrLess90 returns(bool) {
        require(elpAmount > 0, 'WithdrawElp: elpAmount must > 0 ');
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        require(elpRewardPool > elpRewards[msg.sender],"WithdrawElp: ELPReward must > elpRewards[msg.sender]");
        bool ret = false;
        if(elpAmount < elpRewards[msg.sender])
        {
            elpRewards[msg.sender] =  elpRewards[msg.sender].sub(elpAmount);
            ret = elp.transfer(msg.sender, elpAmount);
            require(ret == true,"withdrawElp:elp.transfer must succ !");
        }
        uint256 tmpElpNeed = elpAmount.sub(elpRewards[msg.sender]);
        uint256 elcNeed = 0;
        uint256 relpNeed = 0;
     
        (elcNeed,relpNeed) = computeRelpElcbyWithdrawELP(tmpElpNeed);
        require((elcAmountArray[msg.sender]  > elcNeed)  && (rElpAmountArray[msg.sender]  > relpNeed),"withdrawElp:must have enough elc and relp!");
       
        elc.burn(elcNeed);
        elcAmountArray[msg.sender] = elcAmountArray[msg.sender].sub(elcNeed);
        rElp.burn(relpNeed);
       
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == 0)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
        }else{
             rElpBlockCoinDayArray[msg.sender] =  rElpBlockCoinDayArray[msg.sender].add( (rElpAmountArray[msg.sender].sub(relpNeed)).mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap)));
        }
        rElpBgBlockArray[msg.sender] = block.number;
        rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].sub(relpNeed);
        rElpPoolTotal = rElpPoolTotal.sub(relpNeed);
        rElpCoinDayTotal+=(rElpAmountArray[msg.sender].sub(relpNeed)).mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap));
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
        if(ret){
           emit withdrawELCevent(msg.sender, elcAmount); 
        }else{
           elcAmountArray[msg.sender] =elcAmountArray[msg.sender].add(elcAmount);   
        }
        return ret;
    }
    // get the amount of elc belone to msg.sender
    function getElcAmount() external view returns (uint256){
        return elcAmountArray[msg.sender];
    }
    // user withdraw rELP and send it to user address
    function withdrawRELP(uint256 relpAmount)  external updateRewardELP getExpandElc returns(bool){
        require(relpAmount <= rElpAmountArray[msg.sender],"withdrawRELP:withdraw amount must < rElpAmountArray hold!");
        require(checkProposaler(msg.sender) == false,"withdrawRELP:msgSender must not an proposal in voteDuration!");
        // uRelp put in pool's coin*day 
        if(rElpAmountArray[msg.sender] == relpAmount)
        {
             rElpBlockCoinDayArray[msg.sender] = 0;
        }else{
             rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add((rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap)));
        }
        rElpBgBlockArray[msg.sender] = block.number;
        rElpAmountArray[msg.sender] =  rElpAmountArray[msg.sender].sub(relpAmount);
        rElpPoolTotal = rElpPoolTotal.sub(relpAmount);
         rElpCoinDayTotal+= (rElpAmountArray[msg.sender]).mul( block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap));
        bool ret = rElp.transfer(msg.sender, relpAmount);
        require(ret == true,"withdrawRELP:rElp.transfer must succ");
        emit withdrawRelpevent(msg.sender, relpAmount); 
        return ret;
    }
    // user add rELP to pool, liquidity miner
    function addRELP(uint256 relpAmount) external updateRewardELP getExpandElc returns(bool){
       require(relpAmount > 0,"addRELP:relpAmount >0 ");
        bool ret = rElp.transferFrom(msg.sender, address(this), relpAmount);
        if(ret)
        {
            if(rElpAmountArray[msg.sender] == 0)
            {
                 getLastElcExpandTime[msg.sender] =  block.number;
            }
            rElpBlockCoinDayArray[msg.sender] = rElpBlockCoinDayArray[msg.sender].add( (rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap)));
            rElpBgBlockArray[msg.sender] = block.number;
            rElpPoolTotal = rElpPoolTotal.add( relpAmount);
            rElpCoinDayTotal+=(rElpAmountArray[msg.sender]).mul(block.number.sub(rElpBgBlockArray[msg.sender]).div(adjustGap));
            rElpAmountArray[msg.sender] = rElpAmountArray[msg.sender].add(relpAmount);
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
            elcRiskReserve = elcRiskReserve.sub(elcSellAmount);
            elpAmount = swapToken(true,elcSellAmount);
            elpRiskReserve += elpAmount;
        } else {
           uint256 mintAmount = 0;
           uint256 temp = elcRiskReserve;
           if(elcRiskReserve > 0)
           {
               elcRiskReserve = 0;
               elpAmount = swapToken(true,temp);
               elpRiskReserve += elpAmount;
               mintAmount = elcSellAmount.sub(temp);
           } else  if(elcRiskReserve == 0){
               mintAmount = elcSellAmount;
           }
           require(elc.mint(address(this), mintAmount),"expansion:elc.mint fun must succ!");
           elpAmount = swapToken(true,mintAmount.mul(5).div(100));
           elpRiskReserve += elpAmount;
           rElpCoinDayTotal += rElpPoolTotal.mul( lastExpandTime.sub(relpLastUpdateTime).div(adjustGap) );
           uint256  expandElcforRelp = mintAmount.mul(95).div(100);
           expandHisRec.push(expandRec(rElpCoinDayTotal,block.number,expandElcforRelp,expandElcforRelp.div(rElpCoinDayTotal)));
           rElpCoinDayTotal = 0;
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
        uint256  elpPrice = getELCOraclePrice();
        uint256  elcPrice = getELPOraclePrice();
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
            relpAmount = elpAmount.mul(elpPrice).div(relp_price_90);
            elcAmount  = 0; 
        }
        return (relpAmount, elcAmount);
    }
    // caculate elc and relp amount while withdraw elp
    function computeRelpElcbyWithdrawELP(uint256  elpAmount) internal view returns(uint256 relpAmount, uint256 elcAmount){
        uint256  elpPrice = getELCOraclePrice();
        uint256  elcPrice = getELPOraclePrice();
        uint256  lr = liabilityRatio();
        uint256   relpPrice = computeRelpPrice();  
        if(lr < 90)
        {
           relpAmount = elpPrice.mul(elpAmount).mul(100 - lr).div(100).div(relpPrice);
           elcAmount = elpPrice.mul(elpAmount).mul(lr).div(elcPrice).div(100);    
        }
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
    function contractionComputeElpNeed() internal view returns(uint256) {
        uint256 elcPrice = getELCOraclePrice();
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
       
        if (usdtNeed == 0) {
            return 0;
        }

        if(!usdtToELC)
        {
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
        uint256 elp_price = getELCOraclePrice();
        uint256 elc_price = getELPOraclePrice();
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
        uint256 elp_price = getELCOraclePrice();
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
        uint256 elp_price = getELCOraclePrice();
        uint256 elc_price = getELPOraclePrice();
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
        uint256 tmpRatePerBlock = caculateAvgRatePerBlock(relpLastUpdateTime);
        if (rElpPoolTotal == 0){
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
    function caculateAvgRatePerBlock(uint256 updateTime) internal view returns(uint256){
         uint256 lastRate = caculateRatePerBlock();
         uint256 rateTime = 0;
         uint256 span = (block.number - updateTime).div(adjustGap); 
         uint256 avgRate = 0;
         if(span == 0)
         {
             return lastRate;
         }
         for(uint256 i = 0; i < span; i++)
         {
              rateTime += lastRate.mul(adjustGap).mul(100).div(99);
         }
         rateTime += lastRate.mul(block.number.sub(adjustGap.mul(span)));
         avgRate = rateTime.div(block.number.sub(relpLastUpdateTime));
         return avgRate;
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
       require(bgProposalBlock == 0 || (block.number - bgProposalBlock) < voteDuration,"proposal:must in voteDuration or the first propose");
       require(proposalSender != msg.sender,"proposal: can't propose twice in voteDuration");
       require(rElpAmountArray[proposalSender] < rElpAmountArray[msg.sender],"proposal: new  proposer must have move relp!");
       
       proposalK = detaK; 
       proposalSender = msg.sender;
       against = 0;
       approve = 0;
       turnout = 0;
       turnout += rElpAmountArray[msg.sender];
       approve += rElpAmountArray[msg.sender];
       bgProposalBlock = block.number;
       voterMap[msg.sender].vote = true;
       voterMap[msg.sender].blockNo =  block.number;
       return true;
    }
    // get the first proposal 
    function getProposalTaget() external view returns(uint256){
        if(proposalSender != address(0))
        {
            return proposalK;
        }
        return 0;
    }
    // vote for approve
    function approveVote() external returns (bool){
        require(proposalK > 0,"approveVote:proposalK first element must > 0 ");
        require(bgProposalBlock > 0 && block.number.sub(bgProposalBlock) > voteDuration && block.number.sub(bgProposalBlock) < voteDuration.mul(2));
        if( voterMap[msg.sender].vote == true  && block.number.sub(voterMap[msg.sender].blockNo) < voteDuration)
        {
            return false; 
        }
        turnout += rElpAmountArray[msg.sender];
        approve += rElpAmountArray[msg.sender];
        voterMap[msg.sender].vote = true;
        voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // withdraw proposal 
    function withdrawProposal() external returns (bool) {
        require(proposalK > 0,"withdrawProposal:proposalK element must > 0");
        require( proposalSender == msg.sender ,"withdrawProposal: msg.sender must the proposaler");
        if(block.number.sub(bgProposalBlock) > voteDuration){
            return false;
        }
        proposalK = 0;
        proposalSender = address(0);
        bgProposalBlock = 0;
        return true;
    }
    // vote for against
    function againstVote() external returns (bool){
        require(proposalK > 0,"approveVote:proposalK must > 0 ");
        require(bgProposalBlock > 0 && block.number.sub(bgProposalBlock)  > voteDuration || block.number.sub(bgProposalBlock) < voteDuration.mul(2));
        if( voterMap[msg.sender].vote == true  && block.number.sub(voterMap[msg.sender].blockNo) < voteDuration){
            return false; 
        }
        turnout += rElpAmountArray[msg.sender];
        against += rElpAmountArray[msg.sender];
        voterMap[msg.sender].vote = true;
        voterMap[msg.sender].blockNo =  block.number;
        return true;
    }
    // get vote result
    function votingResult() public returns (bool){
      elcAim =  getAimPrice();
      if(proposalK == 0){
          return false;
      }
      if(bgProposalBlock > 0 &&  block.number.sub(bgProposalBlock) < voteDuration.mul(2)){
          return false;
      }
      bool votingRet = false;
      uint256 electorate = rElp.totalSupply();  
      if(turnout == 0){
          turnout = 1;
      }
      
      uint256 agreeVotes = approve.div(Babylonian.sqrt(electorate));
      uint256 disagreeVotes = against.div(Babylonian.sqrt(turnout)); 
      if(agreeVotes > disagreeVotes){
           k =  proposalK; 
           votingRet = true;
       }
       bgProposalBlock = 0;
       proposalSender= address(0);
       proposalK = 0;
       against = 0;
       approve = 0;
       turnout = 0;
       return votingRet;
    }
    //check if msg.sender voted in voteDuration
    function checkHasVote() external view returns (bool){
      if(bgProposalBlock == 0 && block.number.sub(bgProposalBlock) > voteDuration.mul(2))
      {
           return false;
      }  
      return voterMap[msg.sender].vote;
    }
    // get the approve votes amounts
    function getApproveTotal()external view returns(uint256){
        return approve;
    }
    // get the against votes amounts
    function getAgainstTotal()external view returns(uint256){
        return against;
    }
    //check if msg.sender just an proposer in  voteDuration
    function checkProposaler(address proposaler) internal view returns (bool){
      if(proposalSender == proposaler)
      {
          return true;
      }
      return false;
    }
}
