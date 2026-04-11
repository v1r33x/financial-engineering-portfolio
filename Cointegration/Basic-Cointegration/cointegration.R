############################################################
# 0. LIBRARIES
############################################################
library(quantmod)
library(tidyverse)
library(tseries)
library(zoo)
library(PerformanceAnalytics)
library(xts)

############################################################
# 1. DATA
############################################################
assets <- c("ASML.AS","SAP.DE","SIE.DE","AIR.PA",
            "MC.PA","KER.PA","IFX.DE")

getSymbols(assets, from = "2020-01-01", src = "yahoo")

prices <- do.call(merge, lapply(assets, function(x) Ad(get(x))))
colnames(prices) <- assets

log_prices <- na.omit(log(prices))

############################################################
# 2. ENGLE-GRANGER
############################################################
engle_granger <- function(y, x) {
  model <- lm(y ~ x)
  resid <- residuals(model)
  pval <- adf.test(resid)$p.value
  
  return(c(pval, coef(model)[2]))
}

############################################################
# 3. FIND PAIRS
############################################################
pairs <- combn(colnames(log_prices), 2, simplify = FALSE)

res <- data.frame()

for (p in pairs) {
  tmp <- na.omit(merge(log_prices[,p[1]], log_prices[,p[2]]))
  out <- engle_granger(tmp[,1], tmp[,2])
  
  res <- rbind(res, data.frame(
    pair = paste(p, collapse="-"),
    pval = out[1],
    beta = out[2]
  ))
}

res <- res %>%
  arrange(pval) %>%
  filter(pval < 0.05) %>%
  slice(1:5)

print(res)

############################################################
# 4. BACKTEST (SAFE VERSION)
############################################################
bt <- function(pair, beta, data, tc=0.001) {
  
  p <- strsplit(pair,"-")[[1]]
  m <- na.omit(merge(data[,p[1]], data[,p[2]]))
  colnames(m) <- c("A","B")
  
  spread <- m$A - beta*m$B
  
  mu <- rollapply(spread,60,mean,fill=NA,align="right")
  sd <- rollapply(spread,60,sd,fill=NA,align="right")
  
  z <- (spread-mu)/sd
  
  signal <- rep(0, NROW(z))
  
  for(i in 2:NROW(z)){
    if(is.na(z[i])) next
    
    if(z[i] > 2) signal[i] <- -1
    else if(z[i] < -2) signal[i] <- 1
    else if(abs(z[i]) < 0.5) signal[i] <- 0
    else if(abs(z[i]) > 4) signal[i] <- 0
    else signal[i] <- signal[i-1]
  }
  
  signal <- xts(signal, index(z))
  
  retA <- diff(m$A)
  retB <- diff(m$B)
  
  df <- na.omit(merge(signal, retA, retB))
  colnames(df) <- c("s","rA","rB")
  
  pnl <- df$s * (df$rA - beta*df$rB)
  
  trades <- abs(diff(df$s))
  trades[is.na(trades)] <- 0
  
  pnl <- pnl - trades*tc
  
  return(pnl)
}

############################################################
# 5. RUN BACKTEST
############################################################
plist <- list()

for(i in 1:nrow(res)){
  plist[[ res$pair[i] ]] <- bt(res$pair[i], res$beta[i], log_prices)
}

############################################################
# 6. PORTFOLIO
############################################################
pnl_all <- Reduce(function(x,y) merge(x,y,all=TRUE), plist)

portfolio <- xts(
  rowMeans(pnl_all, na.rm=TRUE),
  order.by=index(pnl_all)
)

portfolio <- na.omit(portfolio)

############################################################
# 7. PERFORMANCE
############################################################
charts.PerformanceSummary(portfolio)

SharpeRatio.annualized(portfolio)
maxDrawdown(portfolio)
Return.cumulative(portfolio)