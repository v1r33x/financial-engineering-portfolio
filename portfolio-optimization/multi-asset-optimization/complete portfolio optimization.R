############################################################
# PROFESSIONAL PORTFOLIO OPTIMIZATION ENGINE
############################################################

# Install packages (run once)
packages <- c("quantmod","PerformanceAnalytics","quadprog","ggplot2","tidyverse")
installed <- packages %in% rownames(installed.packages())
if(any(installed == FALSE)){
  install.packages(packages[!installed])
}

# Load libraries
library(quantmod)
library(PerformanceAnalytics)
library(quadprog)
library(ggplot2)
library(tidyverse)

############################################################
# STEP 1: DOWNLOAD MULTI-ASSET DATA
############################################################

assets <- c(
  "SPY",   # US stocks
  "QQQ",   # Nasdaq
  "IWM",   # Small caps
  "TLT",   # Long treasury bonds
  "GLD",   # Gold
  "VNQ",   # Real estate
  "EEM"    # Emerging markets
)

getSymbols(assets, from="2020-01-01")

prices <- na.omit(merge(
  Cl(SPY),
  Cl(QQQ),
  Cl(IWM),
  Cl(TLT),
  Cl(GLD),
  Cl(VNQ),
  Cl(EEM)
))

colnames(prices) <- assets

############################################################
# STEP 2: COMPUTE RETURNS
############################################################

returns <- na.omit(Return.calculate(prices))

############################################################
# STEP 3: ESTIMATE RISK MODEL
############################################################

mean_returns <- colMeans(returns)

cov_matrix <- cov(returns)

############################################################
# STEP 4: RISK-FREE RATE
############################################################

rf <- 0.02/252   # daily risk-free rate

############################################################
# STEP 5: MINIMUM VARIANCE PORTFOLIO
############################################################

Dmat <- 2*cov_matrix
dvec <- rep(0,ncol(returns))

Amat <- cbind(rep(1,ncol(returns)))
bvec <- 1

solution <- solve.QP(Dmat,dvec,Amat,bvec,meq=1)

w_minvar <- solution$solution
names(w_minvar) <- colnames(returns)

ret_minvar <- sum(w_minvar * mean_returns)

risk_minvar <- sqrt(t(w_minvar) %*% cov_matrix %*% w_minvar)

sharpe_minvar <- (ret_minvar - rf)/risk_minvar

############################################################
# STEP 6: EQUAL WEIGHT PORTFOLIO
############################################################

n <- ncol(returns)

w_equal <- rep(1/n,n)

ret_equal <- sum(w_equal * mean_returns)

risk_equal <- sqrt(t(w_equal) %*% cov_matrix %*% w_equal)

sharpe_equal <- (ret_equal - rf)/risk_equal

############################################################
# STEP 7: MONTE CARLO PORTFOLIO SIMULATION
############################################################

num_portfolios <- 20000

results <- matrix(NA,num_portfolios,3)

weights_store <- matrix(NA,num_portfolios,n)

for(i in 1:num_portfolios){
  
  w <- runif(n)
  w <- w/sum(w)
  
  port_return <- sum(w * mean_returns)
  
  port_risk <- sqrt(t(w) %*% cov_matrix %*% w)
  
  sharpe <- (port_return - rf)/port_risk
  
  results[i,] <- c(port_risk,port_return,sharpe)
  
  weights_store[i,] <- w
}

############################################################
# STEP 8: MAXIMUM SHARPE PORTFOLIO
############################################################

max_index <- which.max(results[,3])

w_sharpe <- weights_store[max_index,]
names(w_sharpe) <- colnames(returns)

ret_sharpe <- results[max_index,2]

risk_sharpe <- results[max_index,1]

sharpe_max <- results[max_index,3]

############################################################
# STEP 9: PRINT PORTFOLIO WEIGHTS
############################################################

cat("\nMinimum Variance Portfolio\n")
print(w_minvar)

cat("\nMaximum Sharpe Portfolio\n")
print(w_sharpe)

cat("\nEqual Weight Portfolio\n")
print(w_equal)

############################################################
# STEP 10: PERFORMANCE COMPARISON
############################################################

comparison <- data.frame(
  Portfolio=c("Min Variance","Max Sharpe","Equal Weight"),
  Return=c(ret_minvar,ret_sharpe,ret_equal),
  Risk=c(risk_minvar,risk_sharpe,risk_equal),
  Sharpe=c(sharpe_minvar,sharpe_max,sharpe_equal)
)

print(comparison)

############################################################
# STEP 11: EFFICIENT FRONTIER
############################################################

df <- data.frame(
  risk = results[,1],
  return = results[,2],
  sharpe = results[,3]
)

ggplot(df,aes(risk,return))+
  geom_point(aes(color=sharpe),alpha=0.5)+
  scale_color_viridis_c()+
  annotate("point",x=risk_minvar,y=ret_minvar,color="red",size=4)+
  annotate("point",x=risk_sharpe,y=ret_sharpe,color="green",size=4)+
  labs(title="Efficient Frontier",
       x="Portfolio Risk",
       y="Expected Return")+
  theme_minimal()

############################################################
# STEP 12: BACKTEST PORTFOLIOS
############################################################

port_minvar <- Return.portfolio(returns,weights=w_minvar)

port_sharpe <- Return.portfolio(returns,weights=w_sharpe)

port_equal <- Return.portfolio(returns,weights=w_equal)

portfolio_returns <- merge(
  port_minvar,
  port_sharpe,
  port_equal
)

colnames(portfolio_returns) <- c(
  "MinVariance",
  "MaxSharpe",
  "EqualWeight"
)

chart.CumReturns(portfolio_returns,
                 legend.loc="topleft",
                 main="Portfolio Performance")

############################################################
# END
############################################################