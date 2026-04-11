
# Pairs Trading — Advanced Cointegration

Economically motivated cointegration strategy with sector filtering and half-life constraints.

## What it does

- Pre-selects 3 sector pairs: **ASML/Infineon** (Semiconductors), **LVMH/Kering** (Luxury), **Siemens/Airbus** (Industrials)
- Filters pairs by cointegration p-value (< 0.10) and mean-reversion half-life (< 80 days)
- Backtests a z-score mean-reversion strategy with 10bps transaction costs

## Improvements over baseline

| Feature | Baseline | Advanced |
|--------|----------|----------|
| Pair selection | Statistical only | Sector-constrained |
| Half-life filter | ✗ | ✓ |
| Universe | 7 assets, all combos | 6 assets, 3 curated pairs |

## Usage

```r
source("advcointegration.R")
```

Data is pulled automatically from Yahoo Finance (2020–present).

## Backtest Result (2020–2026)

Cumulative return of approximately **-70%**, with a max drawdown near **-75%**. Sector filtering and half-life constraints produce marginally better drawdown control than the baseline, but the strategy still deteriorates steadily post-2020. Losses are more evenly distributed across the period compared to the baseline, with no single catastrophic shock.
