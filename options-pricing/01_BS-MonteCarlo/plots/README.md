## Results

### Implied Volatility Surface
![IV Surface](plots/02_implied_volatility_surface.png)

A volatility smile is visible, with higher implied volatility for deep ITM and OTM options. This indicates market pricing of tail risk and deviations from the constant volatility assumption in Black-Scholes.

---

### Market vs Black-Scholes vs Monte Carlo
![Pricing Comparison](plots/03_market_vs_bs_vs_mc.png)

Black-Scholes and Monte Carlo prices closely overlap when using the same implied volatility input, confirming consistency between analytical and simulation-based pricing methods.

---

### Monte Carlo Convergence
![MC Convergence](plots/05_montecarlo_convergence.png)

Monte Carlo estimates converge toward the Black-Scholes benchmark as simulations increase, demonstrating numerical stability and the effect of the law of large numbers.

---

### Option Greeks across Strikes
![Greeks](plots/04_greeks_across_strikes.png)

Delta transitions from near 0 to 1 across strikes, while Gamma peaks around ATM, indicating highest sensitivity. Vega is largest near ATM, showing maximum exposure to volatility changes.

---

### Absolute Pricing Error vs Market
![Pricing Error](plots/06_absolute_pricing_error.png)

Pricing errors are small across strikes, with minor deviations driven by simulated noise. Both Black-Scholes and Monte Carlo remain consistent with implied volatility calibration.
