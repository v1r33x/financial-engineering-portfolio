###########################################################
# PROJECT 1: PORTFOLIO OPTIMIZATION ENGINE
###########################################################

# Install packages (run once)
packages <- c("quantmod","PerformanceAnalytics","quadprog","ggplot2")
installed <- packages %in% rownames(installed.packages())
if(any(installed == FALSE)){
  install.packages(packages[!installed])
}

# Load libraries
library(quantmod)
library(PerformanceAnalytics)
library(quadprog)
library(ggplot2)

###########################################################
# STEP 1: DOWNLOAD STOCK DATA
###########################################################

symbols <- c("AAPL","MSFT","AMZN","GOOGL","TSLA")

getSymbols(symbols, from="2020-01-01", auto.assign=TRUE)

prices <- na.omit(merge(
  Cl(AAPL),
  Cl(MSFT),
  Cl(AMZN),
  Cl(GOOGL),
  Cl(TSLA)
))

colnames(prices) <- symbols

###########################################################
# STEP 2: COMPUTE RETURNS
###########################################################

returns <- na.omit(Return.calculate(prices))

###########################################################
# STEP 3: EXPECTED RETURNS AND COVARIANCE
###########################################################

mean_returns <- colMeans(returns)
cov_matrix <- cov(returns)

###########################################################
# STEP 4: MINIMUM VARIANCE PORTFOLIO
###########################################################

Dmat <- 2 * cov_matrix
dvec <- rep(0, ncol(returns))

Amat <- cbind(rep(1,ncol(returns)))
bvec <- 1

solution <- solve.QP(Dmat, dvec, Amat, bvec, meq=1)

weights <- solution$solution
names(weights) <- colnames(returns)

cat("\nMinimum Variance Portfolio Weights:\n")
print(weights)

###########################################################
# STEP 5: PORTFOLIO RISK AND RETURN
###########################################################

portfolio_return <- sum(weights * mean_returns)

portfolio_risk <- sqrt(t(weights) %*% cov_matrix %*% weights)

cat("\nPortfolio Expected Return:", portfolio_return)
cat("\nPortfolio Risk (Volatility):", portfolio_risk)

###########################################################
# STEP 6: SIMULATE RANDOM PORTFOLIOS
###########################################################

num_portfolios <- 5000

results <- matrix(NA, num_portfolios, 2)

for(i in 1:num_portfolios){
  
  w <- runif(ncol(returns))
  w <- w / sum(w)
  
  port_return <- sum(w * mean_returns)
  
  port_risk <- sqrt(t(w) %*% cov_matrix %*% w)
  
  results[i,] <- c(port_risk, port_return)
}

###########################################################
# STEP 7: PLOT EFFICIENT FRONTIER
###########################################################

ggplot(df, aes(x=risk, y=return)) +
  geom_point(color="blue", alpha=0.4) +
  annotate("point",
           x=portfolio_risk,
           y=portfolio_return,
           color="red",
           size=4) +
  labs(title="Efficient Frontier",
       x="Portfolio Risk (Volatility)",
       y="Expected Return") +
  theme_minimal()

###########################################################
# STEP 8: MAXIMUM SHARPE RATIO PORTFOLIO
###########################################################

num_portfolios <- 10000

results_sharpe <- matrix(NA, num_portfolios, 3)

weights_store <- matrix(NA, num_portfolios, ncol(returns))

for(i in 1:num_portfolios){
  
  w <- runif(ncol(returns))
  w <- w / sum(w)
  
  port_return <- sum(w * mean_returns)
  
  port_risk <- sqrt(t(w) %*% cov_matrix %*% w)
  
  sharpe <- port_return / port_risk
  
  results_sharpe[i,] <- c(port_risk, port_return, sharpe)
  
  weights_store[i,] <- w
}

###########################################################
# FIND MAXIMUM SHARPE PORTFOLIO
###########################################################

max_sharpe_index <- which.max(results_sharpe[,3])

max_sharpe_weights <- weights_store[max_sharpe_index,]

names(max_sharpe_weights) <- colnames(returns)

max_sharpe_risk <- results_sharpe[max_sharpe_index,1]

max_sharpe_return <- results_sharpe[max_sharpe_index,2]

max_sharpe_ratio <- results_sharpe[max_sharpe_index,3]

cat("\nMaximum Sharpe Portfolio Weights:\n")
print(max_sharpe_weights)

cat("\nMax Sharpe Portfolio Return:", max_sharpe_return)
cat("\nMax Sharpe Portfolio Risk:", max_sharpe_risk)
cat("\nMax Sharpe Ratio:", max_sharpe_ratio)

###########################################################
# COMPARE BOTH PORTFOLIOS
###########################################################

cat("\n\n------ COMPARISON ------\n")

cat("\nMinimum Variance Portfolio")
cat("\nReturn:", portfolio_return)
cat("\nRisk:", portfolio_risk)
cat("\nSharpe:", portfolio_return/portfolio_risk)

cat("\n\nMaximum Sharpe Portfolio")
cat("\nReturn:", max_sharpe_return)
cat("\nRisk:", max_sharpe_risk)
cat("\nSharpe:", max_sharpe_ratio)

###########################################################
# PLOT BOTH PORTFOLIOS
###########################################################

df2 <- data.frame(
  risk = results_sharpe[,1],
  return = results_sharpe[,2]
)

ggplot(df2, aes(x=risk, y=return)) +
  geom_point(alpha=0.4, color="blue") +
  annotate("point",
           x=portfolio_risk,
           y=portfolio_return,
           color="red",
           size=4) +
  annotate("point",
           x=max_sharpe_risk,
           y=max_sharpe_return,
           color="green",
           size=4) +
  labs(title="Portfolio Optimization Comparison",
       x="Risk (Volatility)",
       y="Expected Return") +
  theme_minimal()
###########################################################
# END
###########################################################