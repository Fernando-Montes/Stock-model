#!/usr/local/bin/Rscript

# usage: ./Updater.r -v 1 -s 1 -i 1 -p 1 m 1

# options:
# -v verbose
# -s update stocks within an industry
# -p update prices
# -i update indicators
# -t update table
# -m update model predictions

suppressPackageStartupMessages(require(optparse)) # don't say "Loading required package: optparse"

option_list = list(
  make_option(c("-v", "--verbose"), action="store", default=0, type='numeric',
              help="Set -v 1 so it uses verbose"),
  make_option(c("-s", "--stock"), action="store", default=0, type='numeric',
              help="Set -s 1 to update list of stocks to be used"),
  make_option(c("-i", "--indicator"), action="store", default=0, type='numeric',
              help="Set -i 1 to update indicators"),
  make_option(c("-p", "--prices"), action="store", default=0, type='numeric',
              help="Set -p 1 to update stock prices"),
  make_option(c("-t", "--table"), action="store", default=0, type='numeric',
              help="Set -t 1 to update indicator/price table"),
  make_option(c("-m", "--model"), action="store", default=0, type='numeric',
              help="Set -m 1 to update model table")
)
opt = parse_args(OptionParser(option_list=option_list))

verbose = opt$verbose             # -v
update.Stocks = opt$stock         # -s   
update.Indicators = opt$indicator # -i
update.Prices = opt$prices        # -p
update.Table = opt$table          # -t
update.Model = opt$model          # -m

# Loading libraries
suppressPackageStartupMessages(library(quantmod))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(tseries))
suppressPackageStartupMessages(library(zoo))
suppressPackageStartupMessages(library(forecast))
suppressPackageStartupMessages(library(doParallel))
suppressPackageStartupMessages(library(TTR))
suppressPackageStartupMessages(library(lubridate))
suppressPackageStartupMessages(library(caret))

registerDoParallel(cores = 4)

targetPath = "~/Dropbox/Courses/R/StockModel-I/ArchiveFin/"

# Loading list of stocks into stockInfoAll 
fileName <- paste(targetPath, "StockInfoAll.RData", sep="")
load(file = fileName)
# Loading status file
fileName <- paste(targetPath, "status.RData", sep="")
load(file = fileName)

# Updating list of stocks
if (update.Stocks == 1) {
  temp = stockInfoAll
  # Loading additional functions
  source('~/Dropbox/Courses/R/StockModel-I/SymbolBySector.R')
  
  fileName <- paste("~/Dropbox/Courses/R/StockModel-I/", "SectorIndustryInfo.RData", sep="")
  load(fileName)  # loads listAll: all sector and industries
  # Creating a table with the stock info  --------------------
  stockInfoAll <- data.frame(Stock.SYM = character(0),
                             Sector.Num = numeric(0),
                             Industry.Num = numeric(0), stringsAsFactors=FALSE
  )
  for (j in 1:length(listAll[,1])) {
    print(j)
    # Selecting stocks of this sector-industry
    if (class(try( stock <- industry.All.companies(listAll[j,4]), silent = TRUE)) != "try-error" ) {
      if (verbose == 1) print(paste("Industry number ", j, ", No. companies = ", length(stock) ))
      if (length(stock) > 0) {
        for (i in 1:length(stock)) {
          stockInfoAll[nrow(stockInfoAll) + 1, ] <- c(stock[i], listAll[j,2], listAll[j,4])
        }
      }
    }
  }
  temp = rbind(temp, stockInfoAll)
  temp$Stock.SYM = toupper(temp$Stock.SYM)
  stockInfoAll = unique(temp)
}

indicators.updated = 0
prices.updated = 0
# Creating a table with the stock info that has price information only  --------------------
stockInfo <- data.frame(Stock.SYM = character(0),
                        Sector.Num = numeric(0),
                        Industry.Num = numeric(0), stringsAsFactors=FALSE
)
# Loop over all stocks
noStocks = dim(stockInfoAll)[1]
sample.stockInfoAll = sample_n(stockInfoAll, noStocks)  # Randomly sample stocks to be updated
for (i in 1:noStocks) {
# for (i in 1:10) {
  stock = sample.stockInfoAll[i,"Stock.SYM"]
  if (verbose == 1) print( paste("Stock ", stock, " , loop step ", i, " out of ", noStocks)  )
  if (update.Indicators == 1) { # Update indicators
    Fin_Q = data.frame() # In case it does not load next command
    fileName <- paste(targetPath, stock, "-Fin_Q.RData", sep="")
    if ( class(try(load(file = fileName), silent = TRUE)) != "try-error" ) load(fileName)  # loads existing Fin_Q
    if ( class(try( FinStock <- getFinancials(stock, auto.assign = FALSE), silent = TRUE )) != "try-error" ) { # loads new information
      # Income statement
      FinIS = as.data.frame( t(viewFin(FinStock, period = 'Q', "IS")) )
      FinIS$date = rownames(FinIS)
      # Balance sheet
      FinBS = as.data.frame( t(viewFin(FinStock, period = 'Q', "BS")) )
      FinBS$date = rownames(FinBS)
      # Cash flow
      FinCF = as.data.frame( t(viewFin(FinStock, period = 'Q', "CF")) )
      FinCF$date = rownames(FinCF)
      
      temp1 = FinIS %>% full_join(FinBS, by = "date") %>% full_join(FinCF, by = "date")
      temp2 = Fin_Q
      # Removing rows with dates that already have been written (outdated)
      if ( dim(Fin_Q)[1] > 0  ) {
        for ( k in 1:dim(Fin_Q)[1] ) {
          if ( Fin_Q$date[k] %in% temp1$date ) temp2 = temp2[-(temp2$date == Fin_Q$date[k]),]
        }
        indicators.updated = indicators.updated + 1
        Fin_Q = bind_rows(temp1, temp2 )
        Fin_Q = unique(Fin_Q)
        fileName <- paste(targetPath, stock, "-Fin_Q.RData", sep="")
        save(Fin_Q, file = fileName)
        if (stock %in% status$stock) { status[status$stock == stock, 4] = Sys.Date() }
        else {  status = rbind( status, data.frame(stock, dim(Fin_Q)[1], dim(Fin_Q)[2], Sys.Date()) ) }
      }
    }
  }
  if (update.Prices == 1) { # Update stock prices 
    if ( class( try( SYMB_prices <- get.hist.quote(instrument=stock, quote=c("Open", "High", "Low", "Close"), provider="yahoo", compression="d", retclass="zoo", quiet=TRUE), 
                     silent = TRUE) ) != "try-error" ) {
      prices.updated = prices.updated + 1
      if ( dim(SYMB_prices)[1]>10 ) {
        # Code to write info
        fileName <- paste(targetPath, stock, "-prices.RData", sep="")
        save(SYMB_prices, file = fileName)
        stockInfo = rbind(stockInfo, sample.stockInfoAll[i,])
      }
    }
  }
}

fileName <- "~/Dropbox/Courses/R/StockModel-I/ArchiveFin/StockInfoAll.RData"
save(stockInfoAll, file = fileName)

if (update.Prices == 1) { # Update stock prices 
  fileName <- "~/Dropbox/Courses/R/StockModel-I/ArchiveFin/StockInfo.RData"
  save(stockInfo, file = fileName)
}

fileName <- "~/Dropbox/Courses/R/StockModel-I/ArchiveFin/status.RData"
save(status, file = fileName)

# Updating table
if (update.Table == 1) {  

  # Loop over 1...6 months ago
  for (i in seq(1,6,1)) {
    
    # Table today ----- 
    end.date.model = Sys.Date()                        # Today
    ini.date.model = end.date.model %m-% months(6)     # 6 months before to start modeling
    histo.date.model = end.date.model - years(1)       # Model is compared to historical info (1 year earlier)
    apply.date.model = end.date.model %m+% months(i)   # months ahead
    # Prepare table with stock info
    source('~/Dropbox/Courses/R/StockModel-I/PrepareTable.R')          # source prepare table
    table.model <- prepare.table(stockInfoAll, end.date.model, ini.date.model, apply.date.model)
    # Removing stocks that may have problems
    table.model <- table.model[table.model$Price.Model.end > 0.01 & table.model$Price.Min > 0.01,]
    # Adding to table valuations compared to peers
    source('~/Dropbox/Courses/R/StockModel-I/PrepareTableSector.R')    # source prepare.table.sector function
    table.model <- prepare.table.sector(table.model) 
    # Adding historical financial status comparison
    source('~/Dropbox/Courses/R/StockModel-I/StockInfoHistorical.R')   # source add.histo.to.table function
    table.model <- add.histo.to.table(table.model, histo.date.model)
    # Saving table.model
    save(table.model, file = paste(targetPath, as.character(Sys.Date()), "+", i, "m.Rdata", sep = ""))
    
    end.date.model = Sys.Date() %m-% months(i)         # model run today - i months
    ini.date.model = end.date.model %m-% months(6)     # 6 months before to start modeling
    histo.date.model = end.date.model - years(1)       # Model is compared to historical info (1 year earlier)
    apply.date.model = Sys.Date()                      # Today
    # Prepare table with stock info
    table.model <- prepare.table(stockInfoAll, end.date.model, ini.date.model, apply.date.model)
    # Removing stocks that may have problems
    table.model <- table.model[table.model$Price.Model.end > 0.01 & table.model$Price.Min > 0.01 & table.model$actual.win.loss != -100,]
    # Adding to table valuations compared to peers
    table.model <- prepare.table.sector(table.model) 
    # Adding historical financial status comparison
    table.model <- add.histo.to.table(table.model, histo.date.model)
    # Saving table.model
    save(table.model, file = paste(targetPath, as.character(Sys.Date()), "-", i, "m.Rdata", sep = ""))
  }
}

if (update.Model == 1) {  
  # Loading the most recent indicator table table.model
  targetPath <- "~/Dropbox/Courses/R/StockModel-I/ArchiveFin/"
  date.today = Sys.Date()  
  temp = list.files(targetPath, pattern = "2018*") # All the files that may contain indicator information
  diffDate = 20   # Obtain the most recent date less than 20 days
  for (i in 1:length(temp) ) {
    if( length(strsplit(temp[i],"")[[1]])==19 ) { # Correct filename length 
      tempDate = as.Date(substr(temp[i],1,10)) # Extract date file was created
      if (date.today - tempDate < diffDate) { # Obtain the most recent date less than 20 days
        diffDate = date.today - tempDate 
        date.file = tempDate     
      }
    }
  }
  
  # Sourcing prepare.model function
  source('~/Dropbox/Courses/R/StockModel-I/PrepareStockModel.R')
  # Creating stock model with multiple methods ----------------------
  
  # Loop over the different models 3, 6 months
  for (i in seq(1,6,1)) {
    # for (i in seq(3,3,3)) {
    
    # Open table for today's table
    fileName <- paste(targetPath, date.file, "+", i, "m.Rdata", sep = "") 
    load(file = fileName)
    table.pred = table.model
    
    fileName <- paste(targetPath, date.file, "-", i, "m.Rdata", sep = "") 
    load(file = fileName)
    
    # Dividing table into training and test data  ---------------------
    set.seed(235)
    inTrain <- createDataPartition(table.model$actual.win.loss, list = FALSE, p = 0.7)
    my_train <- table.model[inTrain,]
    my_val <- table.model[-inTrain,]
    model_ranger <- prepare.model(my_train, "ranger")    # Model ranger
    my_val$ranger_pred <- predict(model_ranger, my_val)
    model_gbm <- prepare.model(my_train, "gbm")          # Model gbm 
    my_val$gbm_pred <- predict(model_gbm, my_val)
    model_glmnet <- prepare.model(my_train, "glmnet")    # Model glmnet
    my_val$glmnet_pred <- predict(model_glmnet, my_val)
    save(my_val, file = paste(targetPath, date.file, "-", i, "m-validation.Rdata", sep = ""))
    
    # Using created model to make predictions
    table.pred[, paste("ranger_pred_", i, sep="")] <- predict(model_ranger, table.pred)
    table.pred[, paste("gbm_pred_", i, sep="")] <- predict(model_gbm, table.pred)
    table.pred[, paste("glmnet_pred_", i, sep="")] <- predict(model_glmnet, table.pred)
    save(table.pred, file = paste(targetPath, date.file, "+", i, "m-pred.Rdata", sep = ""))
  }
  
}
  
if (verbose == 1) {
  print( paste( "dim(stockInfoAll) ", dim(stockInfoAll) )  )
  print( paste( "dim(status) ", dim(status) )  )
  print( paste( "Indicators updated = ", indicators.updated )  )
  print( paste( "Prices updated = ", prices.updated )  )
  if (update.Table == 1) { print( paste( "Table items  = ", dim(table.model)[1] )  ) }
  else { print("no table created") }
}
