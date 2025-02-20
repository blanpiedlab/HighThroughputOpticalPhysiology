## peakFinder-Heavy.R
 


# 	At the end of writing this script, I should consider at which breakpoints which columns can be dropped. (e.g. flag, pseudoBaseline, etc)

## The dFF for every ROI will be calculated using the pseudo-baseline in data_flagged (pseudoBaseline).  
## Then, peak identification is performed. To enable the user to watch the progress of the script, 
## schmittTrig.R is called, which flags signals and writes 4 plots to the cache. 
# Plot 1. Normalized signal intensity with normalized pseudoBaseline overlay. 
# Plot 2. Close-up of normalized pseudoBaseline.
# Plot 3. dFF with Schmitt Trigger threshold overlay. 
# Plot 4. Binary state in time (schmitt trigger signal ID)  

## The output from this script should be a data.frame with flexibly defined signal epochs. 
## The traceState column will provide a reference for further baseline adjustment in peakFinder-Lite.   



#suppress warnings
oldw <- getOption("warn")
options(warn = -1)

library(gsignal)

tic()


dataset_id = unique(data_flagged$sensor)

if (length(dataset_id) > 1) {
		print("Are you sure you want to run this on multiple sensor datasets?")
		window = 200
		enter = 15
		exit = 50 
	} else if (dataset_id == "GluSnFR3") {
		print(paste0("Flagging outliers for a dataset collected with a fast sensor : " dataset_id))
		window = 200
		enter = 15
		exit = 50
	} else if (dataset_id == "jRGECO|JF646|GCaMP8m") {
		print(paste0("Flagging outliers for a dataset collected with slow sensor : " dataset_id))
		
		window = 200
		enter = 25
		exit = 100
	

	} else if (dataset_id == "GCaMP8f") {
		print(paste0("Flagging outliers for a dataset collected with medium-speed sensor : " dataset_id))
		
		window = 200
		enter = 20
		exit = 75

	}



data <- data_flagged %>%
      	group_by_at(groupers) %>%
      	mutate(normIntensity = intensity/max(intensity,na.rm=TRUE),
      				normBaseline = pseudoBaseline/max(intensity,na.rm=TRUE),
      				normStDev = signal_stdev/max(intensity,na.rm=TRUE),
      				
      				F = intensity,
      				dF = (intensity - pseudoBaseline),
      				dFF = (intensity - pseudoBaseline)/pseudoBaseline,
      				
      				dFF_idx = as.numeric(ifelse(flag=="notOutlier", dFF, "NA")),
    				dFF_signal_v0 = na.locf(dFF_idx, fromLast = FALSE, na.rm = FALSE),				
      				dFF_stdev = rollapply(data=dFF, width=window, FUN=sd,fill=NA, align="center") 
      				) 




drops <- c('dFF_idx',"dFF_signal_v0")  #extraneous data.frame columns clogging up memory
data<- data[ , !(names(data) %in% drops)]


print("Finished calculating dFF.")

toc()



tic()
source("\\\\blanpiedserver/NASShare3/Sam/Sam scripts/Active scripts/pipeline v3/schmittTrig_v2.R") ## import Schmitt Trigger function with plotting


cumplus <- function(y) Reduce(function(a,b) a + b > 0, y, 0, accum=TRUE)[-1]

# threshold over which to identify a peak. Lower trigger = 1.5*sigma, upper trigger = 3.5*sigma
threshold = c(1.5,3.5)    
thresh_stdv = 1.5

peaksHeavy<-data %>%
		group_by_at(groupers) %>%
		do(schmittTrig(dataframe=., 
						time=.$absoluteTime, 
						dFF=.$dFF, 
						normIntensity=.$normIntensity, 
						normBaseline=.$normBaseline,
						#normSmooth = .$normSmooth, 
						normStDev=.$normStDev, 
						threshold=threshold, 
						std=.$dFF_stdev, 
						thresh_stdev=thresh_stdv)
					) %>% 	  
			mutate(interFrame = absoluteTime - lag(absoluteTime),
					LongEntry = case_when(signal == 1 ~ 0,
											lead(signal, n= enter) == 1 ~ 1,
											signal == 0 ~ 0),
					LongExit = case_when(signal == 1 ~ 0,
											lag(signal, n= exit) == 1 ~ 1,
											signal == 0 ~ 0),
					#LongExitTest = 
					cumplus = cumplus(LongEntry - LongExit),
					temp = cumplus - c(0,pmin(0,diff(cumplus))),
					peak_idx = case_when(temp == 1 ~ "isPeak",
										temp == 0 ~ "notPeak")) %>%
			select(-temp) #get rid of extraneous columns

			
drops <- c("temp", "normIntensity", "normBaseline", "pseudoBaseline", "F", "dF", "dFF_stdev",'interFrame','LongEntry','LongExit','cumplus')  #extraneous data.frame columns clogging up memory
peaksHeavy<- peaksHeavy[ , !(names(peaksHeavy) %in% drops)]

										 

print("Finished generously identifying likely peak indices using Schmitt Trigger.")
toc()

#warnings back on
options(warn = oldw)


rm(list=ls()[! ls() %in% c("peaksHeavy","groupers",'showGraphs')])  #clear all vars in memory except for flagged data.


