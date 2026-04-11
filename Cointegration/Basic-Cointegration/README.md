# Pairs Trading — Cointegration Baseline

Engle-Granger cointegration strategy across a 7-asset European equity universe.

## What it does

- Tests all pair combinations from `ASML, SAP, Siemens, Airbus, LVMH, Kering, Infineon`
- Selects the 5 most cointegrated pairs (p < 0.05)
- Backtests a z-score mean-reversion strategy with 10bps transaction costs

## Usage

```r
source("cointegration.R")
```

Data is pulled automatically from Yahoo Finance (2020–present).

## Output

Cumulative return, daily P&L, and drawdown chart via `PerformanceAnalytics`.

## Backtest Result (2020–2026)

The strategy produces a cumulative return of approximately **-75%** over the period. Losses are front-loaded around the COVID shock in early 2020, with steady continued deterioration through 2026 and a max drawdown near **-80%**. This reflects cointegration breakdown under the volatile post-2020 macro regime — the pairs cease to mean-revert as sector correlations structurally shift.
