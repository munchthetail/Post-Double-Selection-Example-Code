//Preamble
	clear all      // clears data, value labels, saved results, and programs
	set more off   // prevents output from pausing with "more"
	
	//Setting working directory to current file location
	global root "C:/Users/you/project" //fill this with the location that you saved the folder
	cd "$root"
	
	//if you uncomment this, it will update all of your installed packages and functions -- this can take a bit to run
	//ado update, update
	
	//these are the packages we need to run the programs
	//this loop will check if you have them installed and install them if you don't
	local installs "pdslasso estout ivreg2 lassopack require"
	
	foreach pkg in `installs' {
		cap which `pkg'
		if _rc != 0 {
			ssc install `pkg', replace
		}
	}

	
//Body
	import delimited birthwt, colrange(2:) clear
	
	//label variables
	local variable bwt "Birth Weight"
	local variable smoke "Smoker"
	
	//race
	gen black = (race==2)
	gen other_race = (race==3)
	
	//controls
	local controls black other_race age lwt ptl ftv ui ht 
	
	//standardize
	foreach v of local controls {
		egen `v'_std = std(`v')
		drop `v'
		rename `v'_std `v'
	}
	
	//baisc OLS
	reg bwt smoke, robust
	estimates store ols
	
	//OLS with controls
	reg bwt smoke `controls', robust
	estimates store ols_controls
	
	//this lasso funciton uses the theory derived tuning parameter
	//partialling out the school and system FEs
	//stratified on school for randomization so that needs to be partialled out
	pdslasso bwt smoke (`controls'), robust
	estimates store pds_lasso
	
	esttab ols ols_controls pds_lasso using Example_IV_Observational.tex, ///
		mtitles("OLS" "OLS+Controls" "PDS-Lasso") ///
		keep(smoke) ///
		nonumbers ///
		b(4) se(4) ///
		star(* 0.10 ** 0.05 *** 0.01) ///
		label nobaselevels ///
		booktabs ///
		replace

//Lasso with cross-validation... there is no pds with built-in cross validation so we do it manually

	//this lasso function uses the cross-validation for the tuning parameter
	//for stable results in cross-validation we need to set a seed
	//lse chooses the largest tuning parameter that is 1SD from the tuning paramter that minimizees out of sample MSE and 
	//nfold(5) chooses the number of folds, 5 is the default
	//plotcv plots how the MSE changes based on the tuning parameter
	/*
	
	//select outcome variables
	cvlasso bwt `controls', lse nfolds(5) seed(1234) plotcv
	local performance_select `e(varXmodel)'
	
	//select treatment variables
	cvlasso smoke `controls', lse nfold(5) seed(1234)
	local treatment_selected `e(varXmodel)'
	
	//run final regression with both sets of variables
	//not the most clean method since we end up with a lot of duplicates
	reg bwt smoke  `performance_select' `treatment_selected', robust
	