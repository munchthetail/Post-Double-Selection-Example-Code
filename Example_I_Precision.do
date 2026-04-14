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
	local installs "pdslasso estout ivreg2 lassopack"
	
	foreach pkg in `installs' {
		cap which `pkg'
		if _rc != 0 {
			ssc install `pkg', replace
		}
	}

	
//Body
	import delimited ResumeNames, colrange(2:) clear
	
	//standardizing the `minimum' variable
	replace minimum = "0" if minimum=="none"
	replace minimum = "999" if minimum=="some"
	destring minimum, replace
	
	quiet sum minimum if minimum != 999
	replace minimum = `r(mean)' if minimum == 999

	//creating dummies from industry 
	tabulate industry, generate(ind_)
	tabulate wanted, generate(want_)
	drop wanted industry
	
	//manually handle callbacks to preserve signs
	rename call call_n
	gen call = (call_n=="yes")
	drop call_n
	
	//make all the variables numeric
	//signs for control coefficients might be mixed up, however this works fine for ethnicity (our treatment) 
		//and the remaining controls aren't of consiquence for our example.
		//Ideally more care could be taken to ensure that dummies match expectations consistently
	local vars gender ethnicity quality city honors volunteer military holes school email computer special college equal requirements reqexp reqcomm reqeduc reqcomp reqorg 
	foreach v of local vars {
		capture confirm string variable `v'
		if !_rc {
			encode `v', gen(`v'_n)
			drop `v'
			rename `v'_n `v'
			replace `v' = 0 if `v'==2
		}
	}
	
	//rescaling all the variables
	local vars2 jobs experience gender quality honors volunteer military holes school email computer special college equal requirements reqexp reqcomm reqeduc reqcomp reqorg minimum 
	foreach v of local vars2 {
		egen `v'_std = std(`v')
		drop `v'
		rename `v'_std `v'
	}
	
	//ajdusting the wanted variable
	label variable ethnicity "African-American Name"
	label variable call "Application Callback"
	
	//baisc OLS
	reg call ethnicity
	estimates store ols
	
	//OLS with controls
	reg call ethnicity `vars' i.city
	estimates store ols_controls
	
	//this lasso funciton uses the theory derived tuning parameter
	//partialling out the city FEs
	pdslasso call ethnicity (`vars2' city), partial(city) robust
	estimates store pds_lasso
	
	//had to make this complicated to print nicely...
	esttab ols ols_controls pds_lasso using Example_I_Precision.tex, ///
		mtitles("OLS" "OLS+Controls" "PDS-Lasso") ///
		keep(ethnicity) ///
		order(ethnicity) ///
		noobs nonumbers ///
		b(4) se(4) ///
		star(* 0.10 ** 0.05 *** 0.01) ///
		booktabs compress ///
		label nobaselevels noomitted ///
		nonotes ///
		addnotes("Standard errors in parentheses" ///
				 "\$^{*}p<0.10\$, \$^{**}p<0.05\$, \$^{***}p<0.01\$") ///
		substitute("\def\sym#1{\ifmmode^{#1}\else\(^{#1}\)\fi}" "" ///
				   "\sym{***}" "$^{***}$" ///
				   "\sym{**}" "$^{**}$" ///
				   "\sym{*}" "$^{*}$") ///
		replace
	
//Lasso with cross-validation... there is no pds with builtin cross validation so we do it manually

	//this lasso function uses the cross-validation for the tuning parameter
	//for stable results in cross-validation we need to set a seed
	//lse chooses the largest tuning parameter that is 1SD from the tuning paramter that minimizees out of sample MSE and 
	//nfold(5) chooses the number of folds, 5 is the default
	//plotcv plots how the MSE changes based on the tuning parameter
	/*
	
	//select outcome variables
	cvlasso call `vars' i.city, lse nfold(5) seed(1234) partial(i.city) plotcv 
	local call_selected `e(varXmodel)'
	
	//select treatment variables
	cvlasso call `vars' i.city, lse nfold(5) partial(i.city) seed(1234)
	local ethnicity_selected `e(varXmodel)'
	
	//run final regression with both sets of variables
	//not the most clean method since we end up with a lot of duplicates
	reg call `ethnicity_selected' `call_selected' i.city, robust
	
	