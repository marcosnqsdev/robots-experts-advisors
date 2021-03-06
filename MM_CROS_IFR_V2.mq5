//+------------------------------------------------------------------+
//|                                               MM_CROS_IFR_V2.mq5 |
//|                                           marcosnqsdev@gmail.com |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "marcosnqsdev@gmail.com"
#property link      "https://www.mql5.com"
#property version   "1.00"

//---
#include <Trade/Trade.mqh>

//---
enum ESTRATEGIA_ENTRADA
  {
   APENAS_MM,  // Apenas Médias Móveis
   APENAS_IFR, // Apenas IFR
   MM_E_IRF,   // Médias mais IFR
  };

//--- Variáveis Input
sinput string s0; //------------Estratégia de Entrada------------
input ESTRATEGIA_ENTRADA estrategia = APENAS_MM; // Estratégia de Entrada Trader

sinput string s1; //------------Médias Móveis------------
input double mm_rapida_periodo = 7; // Periodo Média Rápida
input double mm_lenta_periodo = 21; // Periodo Média Lenta
input ENUM_TIMEFRAMES mm_tempo_grafico = PERIOD_CURRENT; // Tempo Gráfico
input ENUM_MA_METHOD mm_metodo = MODE_EMA; // Método
input ENUM_APPLIED_PRICE mm_preco = PRICE_CLOSE; // Preço Aplicado

sinput string s2; //------------IFR------------
input int ifr_periodo = 5; // Período IFR
input ENUM_TIMEFRAMES ifr_tempo_grafico = PERIOD_CURRENT; // Tempo Gráfico
input ENUM_APPLIED_PRICE ifr_preco = PRICE_CLOSE; // Preço Aplicado

input int ifr_sobrecompra = 70; // Nível de Sobrecompra
input int ifr_sobrevenda = 30; // Nível de Sobrevenda

sinput string s3; //------------------------
input int num_lots = 100; // Número de Lotes
input double pts_TK = 60; // Take Profit
input double pts_SL = 30; // Stop Loss

sinput string s4; //------------------------
input string hora_limite_fecha_op = "17:40"; // Horário Limite Fechar Posição

//+------------------------------------------------------------------+
//| Variáveis para os indicadores                                    |
//+------------------------------------------------------------------+
//--- Médias Móveis
// RÁPIDA - Menor Período
int mm_rapida_Handle; // Handle controlador de média móvel rápida
double mm_rapida_Buffer[]; // Buffer para armazenamento dos dados das médias

// LENTA - Maior Período
int mm_lenta_Handle; // Handle controlador da média móvel lenta
double mm_lenta_Buffer[]; // Buffer para armazenamento dos dados das médias

//--- IFR
int ifr_Handle; // Handle controlador para o IFR
double ifr_Buffer[]; // Buffer para armazenamento dos dados do IFR

//+------------------------------------------------------------------+
//| Variáveis para as funções                                        |
//+------------------------------------------------------------------+
int magic_number = 123456; // Nº mágico do robô

double SL, TK;

MqlRates candles[]; // Armazenar Velas
MqlTick tick; // Armazenar Ticks

//---
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//---
   mm_rapida_Handle = iMA(_Symbol, mm_tempo_grafico, mm_rapida_periodo, 0, mm_metodo, mm_preco);
   mm_lenta_Handle = iMA(_Symbol, mm_tempo_grafico, mm_lenta_periodo, 0, mm_metodo, mm_preco);

   ifr_Handle = iRSI(_Symbol, ifr_tempo_grafico, ifr_periodo, ifr_preco);

   if(mm_rapida_Handle < 0 || mm_lenta_Handle < 0 || ifr_Handle < 0)
     {
      Alert("Erro ao tentar criar handles para o indicador - ERRO: ", GetLastError(), "!");
      return(-1);
     }

   CopyRates(_Symbol, _Period, 0, 4, candles);
   ArraySetAsSeries(candles, true);

   ChartIndicatorAdd(0, 0, mm_rapida_Handle);
   ChartIndicatorAdd(0, 0, mm_lenta_Handle);
   ChartIndicatorAdd(0, 1, ifr_Handle);

//--- Ajustes IND e DOLAR
   if(_Digits == 3)
     {
      SL = pts_SL * 1000;
      TK = pts_TK * 1000;
     }
   else
     {
      SL = pts_SL;
      TK = pts_TK;
     }

//---
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---
   IndicatorRelease(mm_rapida_Handle);
   IndicatorRelease(mm_lenta_Handle);
   IndicatorRelease(ifr_Handle);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Indicadores
   CopyBuffer(mm_rapida_Handle, 0, 0, 4, mm_rapida_Buffer);
   CopyBuffer(mm_lenta_Handle, 0, 0, 4, mm_lenta_Buffer);
   CopyBuffer(ifr_Handle, 0, 0, 4, ifr_Buffer);
   ArraySetAsSeries(mm_rapida_Buffer, true);
   ArraySetAsSeries(mm_lenta_Buffer, true);
   ArraySetAsSeries(ifr_Buffer, true);

//--- Candles
   CopyRates(_Symbol, _Period, 0, 4, candles);
   ArraySetAsSeries(candles, true);

//--- Ticks
   SymbolInfoTick(_Symbol, tick);

//--- Ativar Compra
   bool compra_mm_cros = mm_rapida_Buffer[0] > mm_lenta_Buffer[0] &&
                         mm_rapida_Buffer[2] < mm_lenta_Buffer[2];

   bool compra_ifr = ifr_Buffer[0] <= ifr_sobrevenda;

//--- Ativar Venda
   bool venda_mm_cros = mm_lenta_Buffer[0] > mm_rapida_Buffer[0] &&
                        mm_lenta_Buffer[2] < mm_rapida_Buffer[2];

   bool venda_ifr = ifr_Buffer[0] >= ifr_sobrecompra;

//--- Avalia Estratégia
   bool Comprar = false;
   bool Vender = false;

   if(estrategia == APENAS_MM)
     {
      Comprar = compra_mm_cros;
      Vender = venda_mm_cros;
     }
   else
      if(estrategia == APENAS_IFR)
        {
         Comprar = compra_ifr;
         Vender = venda_ifr;
        }
      else
        {
         Comprar = compra_mm_cros && compra_ifr;
         Vender = venda_mm_cros && venda_ifr;
        }

//---
   bool hasNewCandle = HasNewCandle();

   if(hasNewCandle)
     {
      //--- Realiza Compra
      if(Comprar && PositionSelect(_Symbol) == false)
        {
         desenhaLinhaVertical("Compra", candles[1].time, clrBlue);
         CompraAMercado();
        }

      //--- Realiza Venda
      if(Vender && PositionSelect(_Symbol) == false)
        {
         desenhaLinhaVertical("Venda", candles[1].time, clrRed);
         VendaAMercado();
        }
     }

//---
   if(TimeToString(TimeCurrent(), TIME_MINUTES) == hora_limite_fecha_op && PositionSelect(_Symbol) == true)
     {
      Print("Fim do Tempo Operacional: Encerrar Posições Abertas!");
      FechaPosicao();
     }
  }

//+------------------------------------------------------------------+
//| VISUALIZAÇÃO ESTRATÉGIA                                          |
//+------------------------------------------------------------------+
void desenhaLinhaVertical(string nome, datetime dt, color cor = clrAliceBlue)
  {
   ObjectDelete(0, nome);
   ObjectCreate(0, nome, OBJ_VLINE, 0, dt, 0);
   ObjectSetInteger(0, nome, OBJPROP_COLOR, cor);
  }

//+------------------------------------------------------------------+
//| COMPRA A MERCADO                                                 |
//+------------------------------------------------------------------+
void CompraAMercado()
  {
   double volume = num_lots;
   double price = NormalizeDouble(tick.ask, _Digits);
   double sl = NormalizeDouble(tick.ask - SL*_Point, _Digits);
   double tp = NormalizeDouble(tick.ask + TK*_Point, _Digits);

   trade.Buy(volume, _Symbol, price, sl, tp);

   if(trade.ResultRetcode() == TRADE_RETCODE_PLACED || trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Compra executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| VENDA A MERCADO                                                  |
//+------------------------------------------------------------------+
void VendaAMercado()
  {
   double volume = num_lots;
   double price = NormalizeDouble(tick.bid, _Digits);
   double sl = NormalizeDouble(tick.bid + SL*_Point, _Digits);
   double tp = NormalizeDouble(tick.bid - TK*_Point, _Digits);

   trade.Sell(volume, _Symbol, price, sl, tp);

   if(trade.ResultRetcode() == TRADE_RETCODE_PLACED || trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Venda executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| COMPRA A LIMITE                                                  |
//+------------------------------------------------------------------+
void CompraLimite(double nivel_compra, double tp = 0.0, double sl = 0.0)
  {
   double sl_value = NormalizeDouble(nivel_compra - sl * _Point, _Digits);
   double tp_value = NormalizeDouble(nivel_compra + tp * _Point, _Digits);

   trade.BuyLimit(num_lots, nivel_compra, _Symbol, sl_value, tp_value);

   if(trade.ResultRetcode() == TRADE_RETCODE_PLACED || trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Compra Limite executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| VENDA A LIMITE                                                   |
//+------------------------------------------------------------------+
void VendaLimite(double nivel_venda, double tp = 0.0, double sl = 0.0)
  {
   double sl_value = NormalizeDouble(nivel_venda + sl * _Point, _Digits);
   double tp_value = NormalizeDouble(nivel_venda - tp * _Point, _Digits);

   trade.SellLimit(num_lots, nivel_venda, _Symbol, sl_value, tp_value);

   if(trade.ResultRetcode() == TRADE_RETCODE_PLACED || trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Venda Limite executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| FECHA POSICAO                                                    |
//+------------------------------------------------------------------+
void FechaPosicao()
  {
   ulong ticket = PositionGetTicket(0);
   trade.PositionClose(ticket);

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Fechamento executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| CANCELA ORDEM                                                    |
//+------------------------------------------------------------------+
void CancelaOrdem()
  {
   trade.OrderDelete(OrderGetTicket(0));

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      Print("Ordem de Cancelamento executada com sucesso!");
     }
   else
     {
      Print("Erro de execução. ERRO = ", GetLastError());
      ResetLastError();
     }
  }

//+------------------------------------------------------------------+
//| VERIFICA NOVA VELA                                               |
//+------------------------------------------------------------------+
bool HasNewCandle()
  {
//--- Tempo de abertura
   static datetime last_time = 0;
//--- Tempo atual
   datetime lastbar_time = (datetime) SeriesInfoInteger(Symbol(), Period(), SERIES_LASTBAR_DATE);

   if(last_time == 0)
     {
      last_time = lastbar_time;
      return(false);
     }

   if(last_time != lastbar_time)
     {
      last_time = lastbar_time;
      return(true);
     }

   return(false);
  }
//+------------------------------------------------------------------+
