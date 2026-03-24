# Options Pricing Engine — GARCH(1,1) vs Historical Vol vs Implied Vol

## Overview
Industry-closer options pricing engine applied to real ASML (ASML.AS) market data fetched live from Yahoo Finance. Replaces the constant volatility assumption with GARCH(1,1) forecasts and benchmarks against historical and implied volatility methods.

## Improvements Over Basic Version
- Uses **real market data** (ASML.AS via quantmod) instead of simulated prices
- **GARCH(1,1)** captures volatility clustering and mean reversion
- Compares three volatility methods: GARCH, Historical, and Implied Vol
- Strike range dynamically set as ±20% around live spot price
- Includes GARCH persistence check for stationarity

## Methods Used
- GARCH(1,1) volatility forecasting (rugarch)
- Historical volatility (rolling 30-day annualised)
- Implied volatility extraction
- Black-Scholes + Monte Carlo pricing under each vol method
- Greeks under GARCH volatility

## Outputs
- ASML 1-year price history + rolling volatility
- GARCH 90-day volatility forecast term structure
- Price comparison: GARCH vs Historical vs IV across maturities
- Pricing difference surface (GARCH minus Historical)
- Greeks under GARCH volatility

## Tools & Libraries
- R: RQuantLib, quantmod, rugarch, ggplot2, dplyr, tidyr, gridExtra, zoo
