# JetBoomer AI

JetBoomer AI is a broker-oriented trading system composed of:

- **MT5 Expert Advisor:** `mql5/JetBoomerAI.mq5`
- **Web command center:** `index.html`, `styles.css`, `app.js`
- **Android shell:** `android/`

## 1. Run the website locally

You do not need a framework or npm.

### Option A — Python
From the repository folder:

```bash
python -m http.server 8080
```

Then open:

```
http://localhost:8080
```

### Option B — VS Code
Open the repository in VS Code and use any static-server/Live Server extension.

The website is intentionally safe by default:
- It does **not** contain broker passwords.
- It does **not** pretend that MT5 is connected.
- Demo commands stay local to the browser.
- Risk settings are stored in browser localStorage.
- A real BUY/SELL command requires an authenticated MT5 bridge.

## 2. Install the MT5 Expert Advisor

1. Open MetaTrader 5.
2. Open **File → Open Data Folder**.
3. Open `MQL5/Experts`.
4. Copy `mql5/JetBoomerAI.mq5` into that folder.
5. Open MetaEditor and compile it.
6. Confirm the compiler reports no errors.
7. Attach **JetBoomerAI** to a chart.
8. Start with `EnableTrading=false`.
9. Use **Strategy Tester** with historical data.
10. Only after testing, attach it to a demo account and deliberately enable trading.

### Main safety defaults

- Trading disabled by default
- Risk per trade: 0.50%
- Daily loss lock: 2%
- Peak-equity drawdown lock: 8%
- Maximum open positions: 2
- Maximum trades/day: 4
- Maximum consecutive losses: 3
- Spread guard: 25 points
- ATR-based SL/TP
- Break-even and trailing protection
- Opposite-signal exit
- Friday late-session block
- Margin buffer
- Audit logging

## 3. What "AI" means here

The v3 engine is an **explainable ensemble**, not a fake claim of machine learning.

It scores:
- trend alignment
- EMA structure
- RSI
- ADX regime
- candle quality
- momentum

The score is combined with hard execution and risk controls. A future ML module can be added separately without making the risk layer dependent on an opaque model.

## 4. Testing is required

Do not infer live performance from the dashboard. MT5's Strategy Tester is designed to test and optimize Expert Advisors on historical data, including multi-currency strategies and forward testing. Use realistic spread/commission conditions and test out-of-sample before considering live deployment.

Official MT5 testing documentation:
https://www.metatrader5.com/en/terminal/help/algotrading/testing

## 5. Real web-to-MT5 control

The current website is the UI layer. A production bridge should be:

**Android/Web → HTTPS API + authentication → MT5 bridge/EA → broker**

Never put a broker password or API secret in `index.html`, `app.js`, or the Android app.

The bridge should validate:
- authenticated user/device
- command timestamp/nonce
- symbol
- side
- volume
- maximum risk
- maximum spread
- daily loss lock
- emergency/panic state

The MT5 EA remains the final execution/risk authority.

## 6. Important

This project is software, not a profit guarantee. Backtests can overfit and market conditions change. Validate the exact broker, symbol specification, spread, commission, execution and slippage conditions before any live use.
