# European Pairs Trading — Cointegration Strategy

Statistical arbitrage strategy built on cointegration between European large-cap equities, backtested from 2020 to 2026.

## Overview

Two implementations of an Engle-Granger cointegration pairs trading strategy applied to European stocks across three sectors: **Semiconductors** (ASML, Infineon), **Luxury** (LVMH, Kering), and **Industrials** (Siemens, Airbus).

| File | Description |
|------|-------------|
| `cointegration.R` | Broad universe scan — tests all pair combinations, selects top 5 by p-value |
| `advcointegration.R` | Economically filtered version — pre-selected sector pairs with half-life filtering |

## Strategy Logic

1. **Pair selection** via Engle-Granger cointegration test on log prices
2. **Spread construction** using OLS regression hedge ratio (β)
3. **Signal generation** on rolling 60-day z-score: entry at ±2σ, exit at ±0.5σ, stop at ±4σ
4. **Half-life filter** (advanced version) rejects pairs with mean-reversion > 80 days
5. **Transaction costs** applied at 10bps per trade

## Dependencies

```r
install.packages(c("quantmod", "tidyverse", "tseries", "zoo", 
                   "PerformanceAnalytics", "xts"))
```

## Results

Both versions produce negative cumulative returns over the backtest period, consistent with well-documented cointegration breakdown in post-2020 regimes (COVID disruptions, energy crisis, rate cycle). The advanced version shows marginally better drawdown control via sector and half-life filtering.

## Notes

- Data sourced from Yahoo Finance via `quantmod::getSymbols`
- All prices adjusted for dividends and splits
- Log prices used throughout to ensure stationarity of individual series
