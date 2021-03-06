# ----------------------------------------------------------
# Function to prepare stock model. Returns vector with
# model, train data and validation data
# It uses PrepareTable.R 
# ----------------------------------------------------------

# Stock info available in table
# current stock price
# lowest stock price from end.date.model-months.min to end.date.model 
# highest stock price from end.date.model-months.min to end.date.model
# stock price at end.date.model
# stock price category at end.date.model
# Total assets at end.date.model 
# EV/earnings at end.date.model
# EV/EBITDA at end.date.model
# EV/book value at end.date.model
# EV/revenue at end.date.model
# EV/total cash at end.date.model
# price/(equity/debt) at end.date.model
# prediction for current stock price
# lower bound prediction for current stock price
# industry stock belongs to

prepare.model <- function(my_train, methodchosen) {
  
  #my_train$Price.Category <- factor(my_train$Price.Category, levels = levels(my_train$Price.Category))
  
  if (methodchosen == "ranger") {  
    rangerGrid = expand.grid( .mtry = c(3,4,6,10), .splitrule = c("extratrees"), .min.node.size = c(10, 20) )
    my_model <- train(
      actual.win.loss ~ Price.Model.end.low.ratio + Price.Model.end.high.ratio + #Price.Model.end +
        Ev.earning + Ev.ebitda + Ev.book + Ev.revenue + Ev.cash + EquityAssets.liability + #Assets +
        predicted.hw.win.loss + predicted.hwLB.win.loss + predicted.arima.win.loss + 
        Price.sma.200 + Price.sma.50 + rsi.10 + rsi.50 + dvo +
        Ev.earning.peers + Ev.ebitda.peers + Ev.book.peers + Ev.revenue.peers + Ev.cash.peers + EquityAssets.liability.peers + 
        Price.sma.200.peers + Price.sma.50.peers +
        earning.histo + ebitda.histo + book.histo + revenue.histo + cash.histo + equityAssets.liability.histo + timeDiffFin, 
      method ="ranger", data = my_train, tuneGrid = rangerGrid, importance = 'impurity',
      trControl = trainControl(method = "cv", number = 10, verboseIter = TRUE, allowParallel = TRUE))
  } else if (methodchosen == "gbm") {
    gbmGrid <- expand.grid(.interaction.depth = (1:5) * 2, .n.trees = (1:10)*20, .shrinkage = .1, .n.minobsinnode = (5:15) )
    my_model <- train(
      actual.win.loss ~ Price.Model.end.low.ratio + Price.Model.end.high.ratio + #Price.Model.end +
        Ev.earning + Ev.ebitda + Ev.book + Ev.revenue + Ev.cash + EquityAssets.liability + #Assets +
        predicted.hw.win.loss + predicted.hwLB.win.loss + predicted.arima.win.loss + 
        Price.sma.200 + Price.sma.50 + rsi.10 + rsi.50 + dvo +
        Ev.earning.peers + Ev.ebitda.peers + Ev.book.peers + Ev.revenue.peers + Ev.cash.peers + EquityAssets.liability.peers + 
        Price.sma.200.peers + Price.sma.50.peers +
        earning.histo + ebitda.histo + book.histo + revenue.histo + cash.histo + equityAssets.liability.histo + timeDiffFin, 
      method ="gbm", data = my_train, bag.fraction = 0.5, tuneGrid = gbmGrid,
      trControl = trainControl(method = "cv", number = 10,verboseIter = TRUE, allowParallel = TRUE))
  } else if (methodchosen == "glmnet") {
    my_model <- train(
      actual.win.loss ~ Price.Model.end.low.ratio + Price.Model.end.high.ratio + #Price.Model.end +
        Ev.earning + Ev.ebitda + Ev.book + Ev.revenue + Ev.cash + EquityAssets.liability + #Assets +
        predicted.hw.win.loss + predicted.arima.win.loss + #predicted.hwLB.win.loss + 
        Price.sma.200 + Price.sma.50 + rsi.10 + rsi.50 + dvo +
        Ev.earning.peers + Ev.ebitda.peers + Ev.book.peers + Ev.revenue.peers + Ev.cash.peers + EquityAssets.liability.peers + 
        Price.sma.200.peers + Price.sma.50.peers +
        earning.histo + ebitda.histo + book.histo + revenue.histo + cash.histo + equityAssets.liability.histo + timeDiffFin, 
      method ="glmnet", data = my_train, tuneGrid = expand.grid( alpha = seq(0, 1, length = 20),  
                                                                 lambda = exp(seq(log(1e5), log(1e-5), length.out = 100)) ), 
      preProcess = c("center", "scale"),
      trControl = trainControl(method = "cv", number = 10, verboseIter = TRUE, allowParallel = TRUE))
  }
  
  return(my_model)
  
}

