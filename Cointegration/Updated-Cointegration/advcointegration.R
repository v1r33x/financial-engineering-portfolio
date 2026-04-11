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
# 1. DATA (ECONOMICALLY FILTERED)
############################################################
assets <- c(
  "ASML.AS","IFX.DE",   # Semiconductors
  "MC.PA","KER.PA",     # Luxury
  "SIE.DE","AIR.PA"     # Industrials
)

getSymbols(assets, from = "2020-01-01", src = "yahoo")

prices <- do.call(merge, lapply(assets, function(x) Ad(get(x))))
colnames(prices) <- assets

log_prices <- na.omit(log(prices))

############################################################
# 2. SAFE HALF-LIFE
############################################################
half_life <- function(spread) {
  
  spread <- as.numeric(na.omit(spread))
  
  if(length(spread) < 100) return(Inf)
  
  lagged <- spread[1:(length(spread)-1)]
  current <- spread[2:length(spread)]
  
  delta <- current - lagged
  
  df <- data.frame(delta = delta, lag = lagged)
  
  model <- lm(delta ~ lag, data = df)
  lambda <- coef(model)[2]
  
  if(is.na(lambda) || lambda >= 0) return(Inf)
  
  return(-log(2)/lambda)
}

############################################################
# 3. ENGLE-GRANGER + FILTER
############################################################
engle_granger <- function(y, x) {
  model <- lm(y ~ x)
  resid <- residuals(model)
  
  pval <- adf.test(resid)$p.value
  hl <- half_life(resid)
  
  return(c(pval, coef(model)[2], hl))
}

pairs <- list(
  c("ASML.AS","IFX.DE"),
  c("MC.PA","KER.PA"),
  c("SIE.DE","AIR.PA")
)

res <- data.frame()

for (p in pairs) {
  
  tmp <- na.omit(merge(log_prices[,p[1]], log_prices[,p[2]]))
  
  out <- engle_granger(tmp[,1], tmp[,2])
  
  res <- rbind(res, data.frame(
    pair = paste(p, collapse="-"),
    pval = out[1],
    beta = out[2],
    half_life = out[3]
  ))
}

# FILTER (RELAXED slightly to avoid empty result)
res <- res %>%
  filter(pval < 0.1, half_life < 80)

print(res)

############################################################
# 4. BACKTEST
############################################################
bt <- function(pair, beta, data, tc=0.001) {
  
  p <- strsplit(pair,"-")[[1]]
  m <- na.omit(merge(data[,p[1]], data[,p[2]]))
  colnames(m) <- c("A","B")
  
  spread <- m$A - beta*m$B
  
  mu <- rollapply(spread,60,mean,fill=NA,align="right")
  sd <- rollapply(spread,60,sd,fill=NA,align="right")
  
  z <- (spread-mu)/sd
  
  signal <- rep(0, length(z))
  
  for(i in 2:length(z)){
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

if(nrow(res) == 0){
  stop("No valid pairs found — relax filters or check data")
}

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
