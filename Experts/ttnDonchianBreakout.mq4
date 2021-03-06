//+------------------------------------------------------------------+
//|                                          ttnDonchianBreakout.mq4 |
//|                                              tickelton@gmail.com |
//|                                     https://github.com/tickelton |
//+------------------------------------------------------------------+

/* MIT License

Copyright (c) 2017 tickelton@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#include <stderror.mqh>
#include <stdlib.mqh>

#include <Events.mq4>

#property copyright "tickelton@gmail.com"
#property link      "https://github.com/tickelton"
#property version   "1.00"
#property strict

extern int MagicNumber = 5130;

extern double EquityPerTrade = 1.0;
extern int NperTrade = 1;
extern int ATRPeriod = 20;
extern int SlowMAPeriod = 370;
extern int FastMAPeriod = 12;
extern ENUM_MA_METHOD MAmethod = MODE_EMA;
extern int EntryPerid = 20;
extern int ExitPeriod = 10;
extern double StopATR = 2.0;
extern bool ForceMinLot = false;

enum eLogLevel {
   LevelCritical = 0,
   LevelError = 1,
   LevelWarning = 2,
   LevelInfo = 3,
   LevelDebug = 4,
};
extern eLogLevel LogLevel = LevelError;

int PositionOpen = 0;
int CurrentTicket = 0;
datetime CurrentTimestamp;
enum TradeDirection {
   DirectionInit,
   DirectionBuy,
   DirectionSell,
   DirectionNoTrade,
};
TradeDirection Direction = DirectionInit;
const int DefaultSlippage = 3;
const string eaName = "ttnDonchianBreakout";

int OnInit()
{

   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{

   
}

void OnTick()
{
   bool NewBar = false;
   
   CheckEvents(MagicNumber);

   if(eventBuyClosed_SL > 0 ||
       eventSellClosed_SL > 0 ||
       eventBuyClosed_TP > 0 ||
       eventSellClosed_TP > 0) {
      PositionOpen = 0;
   }
   
   if(CurrentTimestamp != Time[0]) {
      CurrentTimestamp = Time[0];
      NewBar = true;
   }
   
   if(NewBar) {
      if(PositionOpen) {
         CheckClose();
      }
      if(!PositionOpen) {
         CheckOpen();
      }
   }
}

void CheckOpen()
{
   if(Bars <= SlowMAPeriod)
       return;
       
   TradeDirection direction = getDirection();

   if(direction == DirectionBuy) {
      double highVal = iHigh(Symbol(),Period(),iHighest(Symbol(),Period(),MODE_HIGH,EntryPerid,2));
      if(Close[1] > highVal) {
         Direction = DirectionBuy;
         if(!OpenPosition()) {
            if(LogLevel >= LevelError) {
               Print("CheckOpen: Bull open error.");
            }
         }
      }
   } else if(direction == DirectionSell) {
      double lowVal = iLow(Symbol(),Period(),iLowest(Symbol(),Period(),MODE_LOW,EntryPerid,2));
      if(Close[1] < lowVal) {
         Direction = DirectionSell;
         if(!OpenPosition()) {
            if(LogLevel >= LevelError) {
               Print("CheckOpen: Bear open error.");
            }
         }
      }
   }
}

TradeDirection getDirection()
{
   double slowMA = iMA(NULL, 0, SlowMAPeriod, 0, MAmethod, PRICE_CLOSE, 1);
   double fastMA = iMA(NULL, 0, FastMAPeriod, 0, MAmethod, PRICE_CLOSE, 1);
   
   if(fastMA > slowMA) {
      return DirectionBuy;
   } else if(fastMA < slowMA) {
      return DirectionSell;
   } else {
      return DirectionNoTrade;
   }
   
   return DirectionInit;
}

void CheckClose()
{
   if(Direction == DirectionBuy) {
      double lowVal = iLow(Symbol(),Period(),iLowest(Symbol(),Period(),MODE_LOW,ExitPeriod,2));
      if(Close[1] < lowVal) {
         ClosePosition();
      }
   } else if(Direction == DirectionSell) {
      double highVal = iHigh(Symbol(),Period(),iHighest(Symbol(),Period(),MODE_HIGH,ExitPeriod,2));
      if(Close[1] > highVal) {
         ClosePosition();
      }
   }
}

bool OpenPosition()
{
   int ticketNr = -1;
   
   double lotSize = GetLotSize();
   if(lotSize == -1.0) {
      if(LogLevel >= LevelError) {
         Print("PlaceOrder: error lotSize");
      }
      return false;
   }
   
   double stopSize = GetStopSize();
   if(stopSize == -1.0 ||
       stopSize < 0) {
      if(LogLevel >= LevelError) {
         Print("PlaceOrder: error stopSize");
      }
      return false;
   }
   
   if(Direction == DirectionBuy) {
      ticketNr = OrderSend(Symbol(), OP_BUY, lotSize, Ask, DefaultSlippage, stopSize, 0, eaName, MagicNumber, 0, clrBlue);
   } else if(Direction == DirectionSell) {
      ticketNr = OrderSend(Symbol(), OP_SELL, lotSize, Bid, DefaultSlippage, stopSize, 0, eaName, MagicNumber, 0, clrRed); 
   } else {
      if(LogLevel >= LevelDebug) {
         Print("PlaceOrder: error Direction");
      }
      return false;
   }
   
   if(ticketNr != -1) {
      PositionOpen = 1;
      CurrentTicket = ticketNr;
      if(LogLevel >= LevelDebug) {
         PrintFormat("TRADE: dir=%d ticket=%d", Direction, ticketNr);
      }
   }
   
   CheckEvents(MagicNumber);
   if(eventBuyClosed_SL > 0 ||
       eventSellClosed_SL > 0 ||
       eventBuyClosed_TP > 0 ||
       eventSellClosed_TP > 0) {
      PositionOpen = 0;
   }
   
   return true;
}

double GetStopSize()
{
   double curATR = iATR(NULL, 0, ATRPeriod, 1);
   if(curATR == 0.0) {
      if(LogLevel >= LevelError) {
         PrintFormat("Error: ATR=%f", curATR);
      }
      return -1.0;
   }
   
   double stopSize;
   double marketStopLevel = MarketInfo(Symbol(),MODE_STOPLEVEL) * Point;
   
   if(Direction == DirectionBuy) {
      stopSize = Bid - (StopATR * curATR);
      if(stopSize > Ask - marketStopLevel) {
         PrintFormat("SL(%f) > Ask(%f) - minSL(%f)", stopSize, Ask, marketStopLevel);
         return -1.0;
      }
      return stopSize;
   } else if(Direction == DirectionSell) {
      stopSize = Ask + (StopATR * curATR);
      if(stopSize < Bid + marketStopLevel) {
         PrintFormat("SL(%f) < Bid(%f) + minSL(%f)", stopSize, Bid, marketStopLevel);
         return -1.0;
      }
      return stopSize;
   } else {
      if(LogLevel >= LevelError) {
         PrintFormat("Error: GetStopSize: Direction=%d", Direction);
      }
      return -1.0;
   }

   return -1.0;
}

double GetLotSize()
{
   double curATR = iATR(NULL, 0, ATRPeriod, 1) / Point;
   if(curATR == 0.0) {
      if(LogLevel >= LevelError) {
         PrintFormat("Error: ATR=%f", curATR); 
      }
      return -1.0;
   }
   double riskAmount = AccountEquity() * (EquityPerTrade / 100);

   double tickValue = MarketInfo(Symbol(),MODE_TICKVALUE);
   if(Point == 0.001 || Point == 0.00001) tickValue *= 10;

   double lotSize = NperTrade * (riskAmount / (curATR * tickValue));
   
   if(MarketInfo(Symbol(),MODE_LOTSTEP) == 0.1)
   {
      lotSize = NormalizeDouble(lotSize,1);
   }
   else {
      lotSize = NormalizeDouble(lotSize,2);
   }
   
   if(lotSize < MarketInfo(Symbol(),MODE_MINLOT))
   {
      if(LogLevel >= LevelError) {
         PrintFormat("GetLotSize: lotSize=%f < MINLOT", lotSize);
      }
      if (ForceMinLot) {
         return MarketInfo(Symbol(),MODE_MINLOT);
      } else {
         return -1.0;
      }
   } else if(lotSize > MarketInfo(Symbol(),MODE_MAXLOT))
   {
      lotSize = MarketInfo(Symbol(),MODE_MAXLOT);
   }

   return lotSize;

}

void ClosePosition()
{
   if(CurrentTicket == 0) {
      Print("Fatal: cannot close; no current order");
   }
   
   if(OrderSelect(CurrentTicket, SELECT_BY_TICKET) != true) {
      Print("Fatal: cannot select current order");
   }
   
   bool closeRet = false;
   if(Direction == DirectionBuy) {
      closeRet = OrderClose(CurrentTicket, OrderLots(), Bid, DefaultSlippage, clrRed);
   } else if(Direction == DirectionSell) {
      closeRet = OrderClose(CurrentTicket, OrderLots(), Ask, DefaultSlippage, clrBlue);
   }

   if(closeRet != true) {
      Print("Fatal: cannot close current order");
      return;
   }
   
   PositionOpen = 0;
   CurrentTicket = 0;
   Direction = DirectionInit;
}
