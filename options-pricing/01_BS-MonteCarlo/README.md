# Options Pricing Engine — Black-Scholes, Monte Carlo & Greeks

## Overview
A full options pricing engine built in R using simulated market data. Prices European call options across multiple strikes and maturities using Black-Scholes and Monte Carlo, extracts implied volatilities, and computes all major Greeks.

## Methods Used
- Black-Scholes closed-form pricing
- Monte Carlo simulation (100,000 paths)
- Implied Volatility extraction via RQuantLib
- Greeks: Delta, Gamma, Vega, Theta, Rho

## Outputs
- Implied Volatility Surface (3 maturities x 21 strikes)
- Market vs BS vs MC price comparison
- Greeks across strikes
- Monte Carlo convergence curve
- Absolute pricing error vs market

## Limitation
Assumes constant volatility — does not capture volatility clustering or term structure dynamics. See advanced version for GARCH-based improvement.

## Tools & Libraries
- R: RQuantLib, ggplot2, dplyr, tidyr, gridExtra
