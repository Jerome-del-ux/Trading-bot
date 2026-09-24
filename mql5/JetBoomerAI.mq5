//+------------------------------------------------------------------+
//| JetBoomer AI v3 - MT5 Expert Advisor                             |
//| Explainable ensemble + hard risk controls + execution guards.    |
//| IMPORTANT: Backtest on your broker data and use demo first.      |
//+------------------------------------------------------------------+
#property strict
#property version   "3.0"
#property description "JetBoomer AI v3: trend/regime scoring, ATR risk, daily/DD locks, trade management and audit logging."

#include <Trade/Trade.mqh>
CTrade trade;

input ulong  MagicNumber              = 26092401;
input bool   EnableTrading             = false; // SAFETY: enable manually after testing
input double RiskPerTradePct           = 0.50;
input double MaxDailyLossPct           = 2.00;
input double MaxEquityDrawdownPct      = 8.00;
input int    MaxOpenPositions          = 2;
input int    MaxTradesPerDay           = 4;
input int    MaxConsecutiveLosses      = 3;
input int    CooldownMinutes           = 30;
input int    MaxSpreadPoints           = 25;
input int    MaxSlippagePoints         = 20;
input int    StartHour                 = 7;
input int    EndHour                   = 20;
input bool   BlockFridayLate           = true;
input int    FridayStopHour            = 18;
input ENUM_TIMEFRAMES SignalTF         = PERIOD_M15;

input int    FastEMA                   = 21;
input int    SlowEMA                   = 55;
input int    TrendEMA                  = 200;
input int    RSIPeriod                 = 14;
input int    ADXPeriod                 = 14;
input int    ATRPeriod                 = 14;
input double RSIBuyMin                = 52.0;
input double RSISellMax               = 48.0;
input double ADXTrendMin              = 20.0;
input double ATR_SL_Mult              = 1.8;
input double ATR_TP_Mult              = 2.7;
input double MinConfidence            = 0.68;

input bool   UseBreakEven              = true;
input double BreakEvenATR             = 1.0;
input double BreakEvenOffsetPoints    = 2.0;
input bool   UseTrailingStop           = true;
input double TrailATR                 = 1.3;
input bool   CloseOnOppositeSignal    = true;
input bool   OneTradePerBar           = true;

int hFast=INVALID_HANDLE,hSlow=INVALID_HANDLE,hTrend=INVALID_HANDLE;
int hRSI=INVALID_HANDLE,hADX=INVALID_HANDLE,hATR=INVALID_HANDLE;
datetime lastSignalBar=0;
datetime lastEntryTime=0;
double dayStartEquity=0.0;
double peakEquity=0.0;
int stateDay=-1;
bool dailyLock=false;
bool drawdownLock=false;

string GVPeak(){ return StringFormat("JB_%I64u_PEAK",MagicNumber); }
string GVDay(){ return StringFormat("JB_%I64u_DAY",MagicNumber); }
string GVStart(){ return StringFormat("JB_%I64u_START",MagicNumber); }

void Log(string level,string message)
{
   PrintFormat("[JETBOOMER][%s] %s",level,message);
}

int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(MaxSlippagePoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   hFast=iMA(_Symbol,SignalTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(_Symbol,SignalTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hTrend=iMA(_Symbol,SignalTF,TrendEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(_Symbol,SignalTF,RSIPeriod,PRICE_CLOSE);
   hADX=iADX(_Symbol,SignalTF,ADXPeriod);
   hATR=iATR(_Symbol,SignalTF,ATRPeriod);

   if(hFast==INVALID_HANDLE || hSlow==INVALID_HANDLE || hTrend==INVALID_HANDLE ||
      hRSI==INVALID_HANDLE || hADX==INVALID_HANDLE || hATR==INVALID_HANDLE)
   {
      Log("ERROR","Indicator initialization failed.");
      return INIT_FAILED;
   }

   LoadState();
   Log("INFO",StringFormat("Initialized v3.0 on %s %s | trading=%s",_Symbol,EnumToString(SignalTF),EnableTrading?"ON":"OFF"));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(hFast!=INVALID_HANDLE) IndicatorRelease(hFast);
   if(hSlow!=INVALID_HANDLE) IndicatorRelease(hSlow);
   if(hTrend!=INVALID_HANDLE) IndicatorRelease(hTrend);
   if(hRSI!=INVALID_HANDLE) IndicatorRelease(hRSI);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   SaveState();
}

void OnTick()
{
   ResetDailyStateIfNeeded();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>peakEquity){ peakEquity=equity; GlobalVariableSet(GVPeak(),peakEquity); }

   ManagePositions();
   EvaluateHardLocks();

   if(!EnableTrading || dailyLock || drawdownLock) return;
   if(!TradingEnvironmentOK()) return;
   if(CountOurPositions()>=MaxOpenPositions) return;
   if(TradesToday()>=MaxTradesPerDay) return;
   if(ConsecutiveLossesToday()>=MaxConsecutiveLosses) return;
   if(lastEntryTime>0 && (TimeCurrent()-lastEntryTime)<CooldownMinutes*60) return;

   datetime bar=iTime(_Symbol,SignalTF,0);
   if(OneTradePerBar && bar==lastSignalBar) return;
   lastSignalBar=bar;

   double confidence=0.0,atr=0.0;
   int direction=Signal(confidence,atr);
   if(direction==0 || confidence<MinConfidence || atr<=0) return;

   OpenPosition(direction,confidence,atr);
}

void LoadState()
{
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(GlobalVariableCheck(GVPeak())) peakEquity=GlobalVariableGet(GVPeak());
   if(peakEquity<=0) peakEquity=eq;
   GlobalVariableSet(GVPeak(),peakEquity);

   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   stateDay=tm.day_of_year;
   if(GlobalVariableCheck(GVDay()) && (int)GlobalVariableGet(GVDay())==stateDay && GlobalVariableCheck(GVStart()))
      dayStartEquity=GlobalVariableGet(GVStart());
   else
   {
      dayStartEquity=eq;
      GlobalVariableSet(GVDay(),stateDay);
      GlobalVariableSet(GVStart(),dayStartEquity);
   }
}

void SaveState()
{
   GlobalVariableSet(GVPeak(),peakEquity);
   GlobalVariableSet(GVDay(),stateDay);
   GlobalVariableSet(GVStart(),dayStartEquity);
}

void ResetDailyStateIfNeeded()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   if(tm.day_of_year==stateDay) return;

   stateDay=tm.day_of_year;
   dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   dailyLock=false;
   GlobalVariableSet(GVDay(),stateDay);
   GlobalVariableSet(GVStart(),dayStartEquity);
   Log("INFO","New trading day: daily guard reset.");
}

void EvaluateHardLocks()
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);

   if(dayStartEquity>0 && equity<=dayStartEquity*(1.0-MaxDailyLossPct/100.0))
   {
      if(!dailyLock) Log("RISK","Daily loss limit reached. Trading locked.");
      dailyLock=true;
      CloseOurPositions();
   }

   if(peakEquity>0 && equity<=peakEquity*(1.0-MaxEquityDrawdownPct/100.0))
   {
      if(!drawdownLock) Log("RISK","Maximum equity drawdown reached. Trading locked.");
      drawdownLock=true;
      CloseOurPositions();
   }
}

bool TradingEnvironmentOK()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED)) return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;

   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   if(StartHour<EndHour)
   {
      if(tm.hour<StartHour || tm.hour>=EndHour) return false;
   }
   else if(tm.hour<StartHour && tm.hour>=EndHour) return false;

   if(BlockFridayLate && tm.day_of_week==5 && tm.hour>=FridayStopHour) return false;

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   if(bid<=0 || ask<=0) return false;
   double spread=(ask-bid)/_Point;
   if(spread>MaxSpreadPoints) return false;

   return true;
}

// Returns direction and confidence using closed candle data.
// Score is explainable: trend 30%, EMA structure 20%, RSI 15%, ADX/regime 15%,
// candle 10%, momentum 10%.
int Signal(double &confidence,double &atrValue)
{
   double f[3],s[3],tr[3],r[3],adx[3],a[3],c[3],o[3],h[3],l[3];
   if(CopyBuffer(hFast,0,0,3,f)!=3 || CopyBuffer(hSlow,0,0,3,s)!=3 ||
      CopyBuffer(hTrend,0,0,3,tr)!=3 || CopyBuffer(hRSI,0,0,3,r)!=3 ||
      CopyBuffer(hADX,0,0,3,adx)!=3 || CopyBuffer(hATR,0,0,3,a)!=3)
   { confidence=0; atrValue=0; return 0; }

   if(CopyClose(_Symbol,SignalTF,0,3,c)!=3 || CopyOpen(_Symbol,SignalTF,0,3,o)!=3 ||
      CopyHigh(_Symbol,SignalTF,0,3,h)!=3 || CopyLow(_Symbol,SignalTF,0,3,l)!=3)
   { confidence=0; atrValue=0; return 0; }

   atrValue=a[1];
   if(atrValue<=0) { confidence=0; return 0; }

   double buy=0.0,sell=0.0;

   if(c[1]>tr[1]) buy+=0.30; else if(c[1]<tr[1]) sell+=0.30;
   if(f[1]>s[1]) buy+=0.20; else if(f[1]<s[1]) sell+=0.20;

   if(r[1]>=RSIBuyMin && r[1]<75) buy+=0.15;
   else if(r[1]<=RSISellMax && r[1]>25) sell+=0.15;

   if(adx[1]>=ADXTrendMin)
   {
      if(c[1]>tr[1] && f[1]>s[1]) buy+=0.15;
      if(c[1]<tr[1] && f[1]<s[1]) sell+=0.15;
   }
   else
   {
      // Low-ADX regime: reduce confidence rather than inventing a mean-reversion edge.
      buy*=0.85; sell*=0.85;
   }

   double body=MathAbs(c[1]-o[1]);
   double range=MathMax(h[1]-l[1],_Point);
   double bodyRatio=body/range;
   if(c[1]>o[1] && bodyRatio>=0.45) buy+=0.10;
   if(c[1]<o[1] && bodyRatio>=0.45) sell+=0.10;

   if(c[1]>c[2]) buy+=0.10;
   if(c[1]<c[2]) sell+=0.10;

   confidence=MathMax(buy,sell);
   if(buy>=MinConfidence && buy>sell) return 1;
   if(sell>=MinConfidence && sell>buy) return -1;
   return 0;
}

void OpenPosition(int direction,double confidence,double atr)
{
   double price=(direction>0)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   if(price<=0) return;

   double minStop=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double slDist=MathMax(atr*ATR_SL_Mult,minStop+2*_Point);
   double tpDist=MathMax(atr*ATR_TP_Mult,minStop+2*_Point);

   double sl=(direction>0)?price-slDist:price+slDist;
   double tp=(direction>0)?price+tpDist:price-tpDist;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits);
   tp=NormalizeDouble(tp,digits);

   double volume=RiskLotSize(direction,price,sl);
   if(volume<=0) return;

   double margin=0.0;
   ENUM_ORDER_TYPE type=(direction>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcMargin(type,_Symbol,volume,price,margin))
   {
      Log("RISK","OrderCalcMargin failed; trade skipped.");
      return;
   }
   if(margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE)*0.80)
   {
      Log("RISK","Insufficient free-margin buffer; trade skipped.");
      return;
   }

   string comment=StringFormat("JetBoomer v3 %.0f%%",confidence*100.0);
   bool ok=(direction>0)?trade.Buy(volume,_Symbol,0,sl,tp,comment)
                        :trade.Sell(volume,_Symbol,0,sl,tp,comment);

   if(ok)
   {
      lastEntryTime=TimeCurrent();
      Log("TRADE",StringFormat("%s %.2f lots | confidence %.1f%% | SL %.5f | TP %.5f",
         direction>0?"BUY":"SELL",volume,confidence*100.0,sl,tp));
   }
   else Log("ERROR",StringFormat("Order failed: %s",trade.ResultRetcodeDescription()));
}

double RiskLotSize(int direction,double entry,double stop)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*RiskPerTradePct/100.0;
   if(riskMoney<=0) return 0;

   ENUM_ORDER_TYPE type=(direction>0)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   double lossOneLot=0.0;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,stop,lossOneLot)) return 0;
   lossOneLot=MathAbs(lossOneLot);
   if(lossOneLot<=0) return 0;

   double raw=riskMoney/lossOneLot;
   return NormalizeVolume(raw);
}

double NormalizeVolume(double volume)
{
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(minLot<=0 || maxLot<=0 || step<=0) return 0;

   // Never increase risk to satisfy minimum volume.
   if(volume<minLot) return 0;
   volume=MathMin(maxLot,volume);
   volume=MathFloor(volume/step)*step;

   int digits=0;
   double s=step;
   while(digits<8 && MathRound(s)!=s){ s*=10.0; digits++; }
   return NormalizeDouble(volume,digits);
}

int CountOurPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber) count++;
   }
   return count;
}

int TradesToday()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   tm.hour=0; tm.min=0; tm.sec=0;
   datetime start=StructToTime(tm);
   if(!HistorySelect(start,TimeCurrent())) return 0;

   int count=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN) count++;
   }
   return count;
}

int ConsecutiveLossesToday()
{
   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   tm.hour=0; tm.min=0; tm.sec=0;
   datetime start=StructToTime(tm);
   if(!HistorySelect(start,TimeCurrent())) return 0;

   int losses=0;
   for(int i=HistoryDealsTotal()-1;i>=0;i--)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) continue;
      if(HistoryDealGetInteger(deal,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      double net=HistoryDealGetDouble(deal,DEAL_PROFIT)
                +HistoryDealGetDouble(deal,DEAL_SWAP)
                +HistoryDealGetDouble(deal,DEAL_COMMISSION);
      if(net<0) losses++;
      else if(net>0) break;
   }
   return losses;
}

void ManagePositions()
{
   double atr[2];
   if(CopyBuffer(hATR,0,0,2,atr)!=2 || atr[1]<=0) return;

   double conf=0.0,signalATR=0.0;
   int sig=Signal(conf,signalATR);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      string sym=PositionGetString(POSITION_SYMBOL);
      if(sym!=_Symbol) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double current=(type==POSITION_TYPE_BUY)?bid:ask;
      double profitDistance=(type==POSITION_TYPE_BUY)?current-open:open-current;

      if(CloseOnOppositeSignal &&
         ((type==POSITION_TYPE_BUY && sig==-1) || (type==POSITION_TYPE_SELL && sig==1)))
      {
         if(trade.PositionClose(ticket))
            Log("TRADE","Position closed on opposite signal.");
         continue;
      }

      double newSL=sl;
      if(UseBreakEven && profitDistance>=atr[1]*BreakEvenATR)
      {
         double be=(type==POSITION_TYPE_BUY)
            ? open+BreakEvenOffsetPoints*_Point
            : open-BreakEvenOffsetPoints*_Point;

         if(type==POSITION_TYPE_BUY && (sl==0 || be>sl)) newSL=be;
         if(type==POSITION_TYPE_SELL && (sl==0 || be<sl)) newSL=be;
      }

      if(UseTrailingStop && profitDistance>=atr[1]*BreakEvenATR)
      {
         double trail=(type==POSITION_TYPE_BUY)
            ? current-atr[1]*TrailATR
            : current+atr[1]*TrailATR;

         if(type==POSITION_TYPE_BUY && trail>newSL) newSL=trail;
         if(type==POSITION_TYPE_SELL && (newSL==0 || trail<newSL)) newSL=trail;
      }

      int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      newSL=NormalizeDouble(newSL,digits);

      if(newSL>0 && MathAbs(newSL-sl)>2*_Point)
      {
         double minStop=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
         if(type==POSITION_TYPE_BUY && (bid-newSL)>=minStop)
            trade.PositionModify(ticket,newSL,tp);
         if(type==POSITION_TYPE_SELL && (newSL-ask)>=minStop)
            trade.PositionModify(ticket,newSL,tp);
      }
   }
}

void CloseOurPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      trade.PositionClose(ticket);
   }
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD || trans.deal==0) return;
   ulong deal=trans.deal;
   if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=MagicNumber) return;

   double net=HistoryDealGetDouble(deal,DEAL_PROFIT)
             +HistoryDealGetDouble(deal,DEAL_SWAP)
             +HistoryDealGetDouble(deal,DEAL_COMMISSION);
   Log("AUDIT",StringFormat("Deal %I64u | %s | net %.2f",
      deal,EnumToString((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY)),net));
}
//+------------------------------------------------------------------+
