#
# This is a Plumber API. You can run the API by clicking
# the 'Run API' button above.
#
# Find out more about building APIs with Plumber here:
#
#    https://www.rplumber.io/
#

library(plumber)
library(data.table)
library(rstan)
library(resample)

source('R/functions.R')

#' function to make sure requests aren't blocked - known issue with plumber
#' @filter cors
cors <- function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$setHeader("Access-Control-Allow-Methods","*")
    res$setHeader("Access-Control-Allow-Headers", req$HTTP_ACCESS_CONTROL_REQUEST_HEADERS)
    res$status <- 200 
    return(list())
  } else {
    plumber::forward()
  }
  
}

#* Process SUS data
#* @post /sus
function(req) {
  dat <- jsonlite::fromJSON(req$postBody)
  dat <- data.table(dat)
  
  #get sus scores
  df_sub <- dat[, c(2:ncol(dat)), with = FALSE]
  cols <- colnames(df_sub)
  df_sub <- data.table(apply(df_sub, 2, as.numeric))
  colnames(df_sub) <- cols
  odds <- seq(1, ncol(df_sub) - 1, by = 2)
  evens <- seq(2, ncol(df_sub), by = 2)
  sus_scores <- apply(df_sub, 1, sus_converter, odds, evens)
  
  sub <-list(N=length(sus_scores),
             y=sus_scores,
             sigma=sd(sus_scores))
  
  new.fit <- stan(file = 'R/stanmod.stan', data = sub,refresh=0)
  #mod <- readRDS('stanmod.rds')
  #new.fit <- stan(model_code = 'mod', data = sub,refresh=0)
  
  samps <- as.vector(extract(new.fit)$mu)
  lower<-summary(new.fit, pars = c("mu"), probs = c(0.05, 0.95))$summary[[4]]
  upper<-summary(new.fit, pars = c("mu"), probs = c(0.05, 0.95))$summary[[5]]
  
  ci <- matrix(c(lower, upper), nrow = 1)
  bayes <- list(sus_scores = sus_scores, ci = ci[1,], replicates = samps)
  
  
  
  N.bootstrap <- 1000
  ci.hw.increase <- 0
  b <- bootstrap(sus_scores, mean(sus_scores), R = N.bootstrap)  
  ci <- CI.bca(b, probs = c(0.025-ci.hw.increase, 0.975+ci.hw.increase), expand = TRUE)
  boot <- list(sus_scores = sus_scores, ci = ci[1,], replicates = b$replicates)

  #out <- list(sus_scores = sus_scores, ci = ci[1,], replicates = samps)
  out <- list(bayes, boot)
  return(out)
}
