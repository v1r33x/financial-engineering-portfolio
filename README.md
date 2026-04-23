# Financial Engineering Portfolio

**Rahul Kumar Rai** | MSc Actuarial & Financial Engineering, KU Leuven  
[linkedin.com/in/rahul-rai-a1876112a](https://linkedin.com/in/rahul-rai-a1876112a)

---

## Overview

This repository contains quantitative finance and actuarial projects built during the MSc in Actuarial & Financial Engineering at KU Leuven. Projects span systematic equity strategies, actuarial mortality modelling, credit risk, and options pricing — implemented in R with real market and regulatory data.

---

## Projects

### [Walk-Forward Factor Model](./factor-model)
**Fama-French 5 + Momentum | Rolling OLS | Long-Short Portfolio**

Systematic equity factor model on 23 European large-caps. Strict walk-forward OLS estimation prevents look-ahead bias. Extended analysis includes IC decay across 6 horizons, leave-one-out factor attribution (momentum dominant at IC drop 0.0136), transaction cost break-even (~180 bps), regime-conditional performance (IC 3x stronger in bear markets), and out-of-sample validation on FTSE 100 retaining 82% of signal strength.

- Annualised Sharpe: **0.446** | Mean IC: **0.0435** | Hit Rate: **60%**
- Languages: R | Data: Yahoo Finance, Ken French Data Library

---

### [Stochastic Mortality Modelling & Life Insurer ALM](./insurance-ALM)
**Lee-Carter + CBD | Multi-Country | Solvency II Stress Testing**

Full actuarial pipeline for stochastic mortality modelling across Belgium, UK, and Netherlands. Lee-Carter and CBD models fitted to HMD data; mortality projected 30 years forward via 1,000 Monte Carlo simulations. Life insurer portfolio valued under Solvency II standard formula stresses. Longevity VaR computed at 99.5th percentile using internal model methodology.

- Combined stress solvency ratio: **84.8%** | Longevity VaR capital shortfall: **EUR 88,750**
- UK mortality improvement turned positive in 2010s — drift assumption limitation documented
- Languages: R | Data: Human Mortality Database

---

### [Credit Risk Modelling — Merton Structural Model](./credit-risk)
**Snapshot vs MLE vs Empirical PD | Gaussian Copula Portfolio VaR**

Merton (1974) structural credit risk model on 9 European large-caps across 6 sectors. Three progressively sophisticated implementations: snapshot Merton, MLE estimation using full price history (~500 daily inversions per company), and empirical PD calibration using Moody's historical default rates. Portfolio credit VaR computed via Gaussian copula under three correlation stress scenarios.

- MLE corrects Volkswagen PD from **99.9% → 2.47%** | BNP Paribas from **43.8% → 0.07%**
- Bayer confirmed as genuinely stressed at **Ba/1.10%** empirical PD post-Monsanto
- Languages: R | Data: Yahoo Finance, Moody's Annual Default Study 2023

---

### [Cointegration-Based Pairs Trading](./Cointegration)
**Engle-Granger | European Large-Caps | Z-Score Signal Generation**

Statistical arbitrage strategy using cointegration analysis on European large-cap equity pairs. Engle-Granger two-step testing identifies cointegrated pairs; z-score signal generation triggers long-short entries. Advanced version adds sector-constrained pair selection and half-life filtering.

- Languages: R | Data: Yahoo Finance

---

### [Portfolio Optimization](./portfolio-optimization)
**Mean-Variance | Multi-Asset ETF | Efficient Frontier**

Mean-variance portfolio optimization across single-stock and multi-asset ETF universes. Implements minimum variance and maximum Sharpe portfolios via quadratic programming and Monte Carlo simulation. Efficient frontier visualization with annotated optimal portfolios.

- Languages: R | Data: Yahoo Finance

---

### [Options Pricing](./options-pricing)
**Black-Scholes | Numerical Methods | Greeks**

Implementation and comparison of options pricing approaches including analytical Black-Scholes and numerical methods. Greeks computation and sensitivity analysis.

- Languages: R

---

## Technical Skills Demonstrated

| Area | Methods |
|---|---|
| Systematic Equity | Factor models, walk-forward validation, IC analysis, signal research |
| Actuarial | Lee-Carter, CBD, stochastic mortality projection, Solvency II, ALM |
| Credit Risk | Merton structural model, MLE estimation, Gaussian copula, portfolio VaR |
| Statistical Arbitrage | Cointegration, Engle-Granger, pairs trading, z-score signals |
| Portfolio Construction | Mean-variance optimisation, efficient frontier, Sharpe maximisation |
| Languages | R, Python |
| Data Sources | Yahoo Finance, Ken French Data Library, Human Mortality Database, Moody's |
