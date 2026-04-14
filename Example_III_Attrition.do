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

	//ftools - check then install from GitHub with compilation
	cap which ftools
	if _rc != 0 {
		cap ado uninstall ftools
		net install ftools, from("https://raw.githubusercontent.com/sergiocorreia/ftools/master/src/") replace
		ftools, compile
		mata: mata mlib index
	}

	//reghdfe - check then install from GitHub
	cap which reghdfe
	if _rc != 0 {
		cap ado uninstall reghdfe
		net install reghdfe, from("https://raw.githubusercontent.com/sergiocorreia/reghdfe/master/src/") replace
	}
	
//Body
	import delimited STAR, colrange(2:) clear
	
	//keep only regular and small class assignments
	keep if star1 == "small" | star1 == "regular"
	
	//treatment combined math and reading
	gen performance = math1+read1
	
	//treatment assignment to small class
	gen treatment = (star1=="small")
	
	//labeling variables
	label variable performance "First Grade Test Scores"
	label variable treatment "Small Class Assignment"
	
	//making dummies from categorical variables
	//we're omitting everthing but these categories
	keep if (ethnicity=="afam" | ethnicity=="cauc")
	gen black = (ethnicity=="afam")
	gen white = (ethnicity=="cauc")
	
	//free lunches
	gen freelunch = (lunch1=="free")
	
	//teacher degree
	gen teacher_ba = (degree1=="bachelor")
	gen teacher_ma = (degree1=="master"|degree1=="specialist")
	
	//teacher ethnicity
	gen teacher_black = (tethnicity1=="afam")
	
	//teacher career step
	gen ladder_level1 = (ladder1=="level1")
	gen ladder_level2 = (ladder1=="level2")
	gen ladder_level3 = (ladder1=="level3")
	gen ladder_apprentice = (ladder1=="apprentice")
	gen ladder_probation = (ladder1=="probation")
	
	//school type
	gen school_inner = (school1=="inner-city")
	gen school_rural = (school1=="rural")
	gen school_suburban = (school1=="suburban")
	
	//date year-quarter 
	gen birthdate = quarterly(birth, "YQ")

	//controls
	local controls black white freelunch teacher_ba teacher_ma teacher_black ladder_level1 ladder_level2 ladder_level3 ladder_apprentice ladder_probation school_inner school_rural school_suburban birthdate experience1 
	
	//scaling controls
	foreach v of local controls {
		egen `v'_std = std(`v')
		drop `v'
		rename `v'_std `v'
	}
	
	//baisc OLS
	reg performance treatment, robust cluster(schoolid1)
	estimates store ols
	
	//OLS with controls
	reghdfe performance treatment `controls', vce(cluster schoolid1) absorb(schoolid1 system1)
	estimates store ols_controls
	
	//this lasso funciton uses the theory derived tuning parameter
	//partialling out the school and system FEs
	//stratified on school for randomization so that needs to be partialled out
	pdslasso performance treatment (`controls' schoolid1 system1), partial(schoolid1 system1) robust cluster(schoolid1)
	estimates store pds_lasso
	
	esttab ols ols_controls pds_lasso using Example_III_Attrition.tex, ///
		mtitles("OLS" "OLS+Controls" "PDS-Lasso") ///
		keep(treatment) ///
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
	cvlasso performance `controls' i.schoolid1 i.system1, lse nfolds(5) seed(1234) plotcv partial(i.schoolid1 i.system1) 
	local performance_select `e(varXmodel)'
	
	//select treatment variables
	cvlasso treatment `controls' i.schoolid1 i.system1, lse nfold(5) seed(1234) partial(i.schoolid1 i.system1) 
	local treatment_selected `e(varXmodel)'
	
	//run final regression with both sets of variables
	//not the most clean method since we end up with a lot of duplicates
	reghdfe performance treatment `performance_select' `treatment_selected', vce(cluster schoolid1) absorb(schoolid1 system1)
	
	