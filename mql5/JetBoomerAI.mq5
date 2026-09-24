//+------------------------------------------------------------------+
//| JetBoomer AI v2 - MT5 Expert Advisor                            |
//| Multi-factor trend/momentum engine with hard risk controls.      |
//| Designed for Strategy Tester first; demo before live trading.   |
//+------------------------------------------------------------------+
#property strict
#property version   "2.0"
#property description "JetBoomer AI: multi-factor scoring, ATR risk, drawdown and trade guards."

#include <Trade/Trade.mqh>
CTrade trade;

input ulong  MagicNumber            = 26092401;
input double RiskPerTradePct        = 0.50;
input double MaxDailyLossPct        = 2.00;
input double MaxEquityDrawdownPct   = 8.00;
input int    MaxOpenPositions       = 2;
input int    MaxSpreadPoints        = 25;
input int    StartHour              = 7;
input int    EndHour                = 20;
input ENUM_TIMEFRAMES SignalTF      = PERIOD_M15;

input int    FastEMA                 = 21;
input int    SlowEMA                 = 55;
input int    TrendEMA                = 200;
input int    RSIPeriod               = 14;
input double RSIBuyMin              = 52.0;
input double RSISellMax             = 48.0;
input int    ATRPeriod               = 14;
input double ATR_SL_Mult             = 1.8;
input double ATR_TP_Mult             = 2.7;
input double MinConfidence          = 0.68;

input bool   UseBreakEven            = true;
input double BreakEvenATR            = 1.0;
input bool   UseTrailingStop         = true;
input double TrailATR                = 1.3;
input bool   CloseOnOppositeSignal   = true;
input bool   OneTradePerBar         = true;

int hFast=-1,hSlow=-1,hTrend=-1,hRSI=-1,hATR=-1;
datetime lastBar=0;
double dayStartEquity=0.0, peakEquity=0.0;
int dayOfYear=-1;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(20);

   hFast=iMA(_Symbol,SignalTF,FastEMA,0,MODE_EMA,PRICE_CLOSE);
   hSlow=iMA(_Symbol,SignalTF,SlowEMA,0,MODE_EMA,PRICE_CLOSE);
   hTrend=iMA(_Symbol,SignalTF,TrendEMA,0,MODE_EMA,PRICE_CLOSE);
   hRSI=iRSI(_Symbol,SignalTF,RSIPeriod,PRICE_CLOSE);
   hATR=iATR(_Symbol,SignalTF,ATRPeriod);

   if(hFast<0 || hSlow<0 || hTrend<0 || hRSI<0 || hATR<0)
      return INIT_FAILED;

   ResetDailyState(true);
   return INIT_SUCCEEDED;
}
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hFast); IndicatorRelease(hSlow); IndicatorRelease(hTrend);
   IndicatorRelease(hRSI); IndicatorRelease(hATR);
}
//+------------------------------------------------------------------+
void OnTick()
{
   ResetDailyState(false);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity>peakEquity) peakEquity=equity;

   ManagePositions();

   if(!TradingGuardsOK()) return;

   if(OneTradePerBar)
   {
      datetime t=iTime(_Symbol,SignalTF,0);
      if(t==lastBar) return;
      lastBar=t;
   }

   if(CountOurPositions()>=MaxOpenPositions) return;

   double confidence=0.0;
   int direction=Signal(confidence);

   if(direction==1 && confidence>=MinConfidence)
      OpenPosition(ORDER_TYPE_BUY,confidence);
   else if(direction==-1 && confidence>=MinConfidence)
      OpenPosition(ORDER_TYPE_SELL,confidence);
}
//+------------------------------------------------------------------+
void ResetDailyState(bool force)
{
   MqlDateTime now; TimeToStruct(TimeCurrent(),now);
   int d=now.day_of_year;
   if(force || d!=dayOfYear)
   {
      dayOfYear=d;
      dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(peakEquity<=0) peakEquity=dayStartEquity;
   }
}
//+------------------------------------------------------------------+
bool TradingGuardsOK()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)) return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED)) return false;

   MqlDateTime tm; TimeToStruct(TimeCurrent(),tm);
   if(StartHour<EndHour)
   {
      if(tm.hour<StartHour || tm.hour>=EndHour) return false;
   }
   else
   {
      if(tm.hour<StartHour && tm.hour>=EndHour) return false;
   }

   double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double spread=(ask-bid)/_Point;
   if(spread>MaxSpreadPoints) return false;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(dayStartEquity>0 && equity <= dayStartEquity*(1.0-MaxDailyLossPct/100.0))
   {
      CloseOurPositions();
      return false;
   }
   if(peakEquity>0 && equity <= peakEquity*(1.0-MaxEquityDrawdownPct/100.0))
   {
      CloseOurPositions();
      return false;
   }
   return true;
}
//+------------------------------------------------------------------+
//| Ensemble "AI" score: trend + momentum + candle confirmation.    |
//| This is deterministic and auditable, not a claim of ML magic.   |
//+------------------------------------------------------------------+
int Signal(double &confidence)
{
   double f[3],s[3],tr[3],r[3],a[3],c[3],o[3],h[3],l[3];
   if(CopyBuffer(hFast,0,0,3,f)!=3 || CopyBuffer(hSlow,0,0,3,s)!=3 ||
      CopyBuffer(hTrend,0,0,3,tr)!=3 || CopyBuffer(hRSI,0,0,3,r)!=3 ||
      CopyBuffer(hATR,0,0,3,a)!=3) { confidence=0; return 0; }

   if(CopyClose(_Symbol,SignalTF,0,3,c)!=3 || CopyOpen(_Symbol,SignalTF,0,3,o)!=3 ||
      CopyHigh(_Symbol,SignalTF,0,3,h)!=3 || CopyLow(_Symbol,SignalTF,0,3,l)!=3)
   { confidence=0; return 0; }

   // Use the last closed candle (index 1).
   double buy=0.0,sell=0.0;
   if(c[1]>tr[1]) buy+=0.30; else sell+=0.30;
   if(f[1]>s[1]) buy+=0.25; else sell+=0.25;

   if(r[1]>=RSIBuyMin && r[1]<75) buy+=0.20;
   if(r[1]<=RSISellMax && r[1]>25) sell+=0.20;

   double body=MathAbs(c[1]-o[1]);
   double range=MathMax(h[1]-l[1],_Point);
   if(c[1]>o[1] && body/range>=0.45) buy+=0.15;
   if(c[1]<o[1] && body/range>=0.45) sell+=0.15;

   if(c[1]>c[2]) buy+=0.10;
   if(c[1]<c[2]) sell+=0.10;

   double total=buy+sell;
   if(total<=0){confidence=0;return 0;}
   confidence=MathMax(buy,sell);

   if(buy>=0.68 && buy>sell) return 1;
   if(sell>=0.68 && sell>buy) return -1;
   return 0;
}
//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type,double confidence)
{
   double atr[2];
   if(CopyBuffer(hATR,0,0,2,atr)!=2 || atr[1]<=0) return;

   double price=(type==ORDER_TYPE_BUY)?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double slDist=atr[1]*ATR_SL_Mult;
   double tpDist=atr[1]*ATR_TP_Mult;

   double sl=(type==ORDER_TYPE_BUY)?price-slDist:price+slDist;
   double tp=(type==ORDER_TYPE_BUY)?price+tpDist:price-tpDist;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);

   double volume=RiskLotSize(slDist);
   if(volume<=0) return;

   string comment=StringFormat("JetBoomer AI %.0f%%",confidence*100.0);
   bool ok=false;
   if(type==ORDER_TYPE_BUY) ok=trade.Buy(volume,_Symbol,0,sl,tp,comment);
   else ok=trade.Sell(volume,_Symbol,0,sl,tp,comment);

   if(!ok) Print("JetBoomer order failed: ",trade.ResultRetcodeDescription());
}
//+------------------------------------------------------------------+
double RiskLotSize(double stopDistance)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskMoney=equity*RiskPerTradePct/100.0;

   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(stopDistance<=0 || tickSize<=0 || tickValue<=0) return 0;

   double lossPerLot=(stopDistance/tickSize)*tickValue;
   if(lossPerLot<=0) return 0;

   double raw=riskMoney/lossPerLot;
   double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0) step=minLot;

   raw=MathFloor(raw/step)*step;
   raw=MathMax(minLot,MathMin(maxLot,raw));
   return NormalizeDouble(raw,2);
}
//+------------------------------------------------------------------+
int CountOurPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber) count++;
   }
   return count;
}
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr[2];
   if(CopyBuffer(hATR,0,0,2,atr)!=2 || atr[1]<=0) return;

   double conf; int sig=Signal(conf);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=MagicNumber) continue;

      long type=PositionGetInteger(POSITION_TYPE);
      double open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);
      double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
      double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);
      double current=(type==POSITION_TYPE_BUY)?bid:ask;

      if(CloseOnOppositeSignal && ((type==POSITION_TYPE_BUY && sig==-1) ||
                                   (type==POSITION_TYPE_SELL && sig==1)))
      {
         trade.PositionClose(ticket);
         continue;
      }

      double profitDistance=(type==POSITION_TYPE_BUY)?current-open:open-current;
      double newSL=sl;

      if(UseBreakEven && profitDistance>=atr[1]*BreakEvenATR)
      {
         double be=(type==POSITION_TYPE_BUY)?open+2*_Point:open-2*_Point;
         if(type==POSITION_TYPE_BUY && (sl==0 || be>sl)) newSL=be;
         if(type==POSITION_TYPE_SELL && (sl==0 || be<sl)) newSL=be;
      }

      if(UseTrailingStop && profitDistance>=atr[1]*BreakEvenATR)
      {
         double trail=(type==POSITION_TYPE_BUY)?current-atr[1]*TrailATR:current+atr[1]*TrailATR;
         if(type==POSITION_TYPE_BUY && trail>newSL) newSL=trail;
         if(type==POSITION_TYPE_SELL && (newSL==0 || trail<newSL)) newSL=trail;
      }

      if(newSL>0 && MathAbs(newSL-sl)>2*_Point)
         trade.PositionModify(ticket,newSL,tp);
   }
}
//+------------------------------------------------------------------+
void CloseOurPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         trade.PositionClose(ticket);
   }
}
//+------------------------------------------------------------------+
