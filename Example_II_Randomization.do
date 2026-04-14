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
	import delimited randhealth, colrange(2:) clear
	
	//treatment is a zero copay plan
	gen zero_copay = (plan==1 | plan==11 | plan==13)
	
	//logging doctor visits
	gen ln_doc_vis = log(mdvis)
	
	//listing controls
	local controls black female xage child fchild educdec mhi disea physlm xghindx hlthg hlthf hlthp income linc num lnum lfam mdeoff lpi pioff time
	
	//scaling controls
	foreach v of local controls {
		egen `v'_std = std(`v')
		drop `v'
		rename `v'_std `v'
	}
	
	
	//ajdusting the wanted variable
	label variable ln_doc_vis "Percentage Change in Doctor Visits"
	label variable zero_copay "Zero Copay Plan"
	
	//baisc OLS
	reg ln_doc_vis zero_copay, robust cluster(zper)
	estimates store ols
	
	//OLS with controls
	reghdfe ln_doc_vis zero_copay `controls', vce(cluster zper) absorb(site year)
	estimates store ols_controls
	
	//this lasso funciton uses the theory derived tuning parameter
	//partialling out the site and year FEs
	//stratified on site for randomization so that needs to be partialled out
	//we assume there are strong year FEs so those are partialled out
	pdslasso ln_doc_vis zero_copay (`controls' site year), partial(site year) robust cluster(zper)
	estimates store pds_lasso
	
	esttab ols ols_controls pds_lasso using Example_II_Attrition.tex, ///
		mtitles("OLS" "OLS+Controls" "PDS-Lasso") ///
		keep(zero_copay) ///
		nonumbers ///
		b(4) se(4) ///
		star(* 0.10 ** 0.05 *** 0.01) ///
		label nobaselevels ///
		booktabs ///
		replace 
		
//Lasso with cross-validation... there is no pds with builtin cross validation so we do it manually

	//this lasso function uses the cross-validation for the tuning parameter
	//for stable results in cross-validation we need to set a seed
	//lse chooses the largest tuning parameter that is 1SD from the tuning paramter that minimizees out of sample MSE and 
	//nfold(5) chooses the number of folds, 5 is the default
	//plotcv plots how the MSE changes based on the tuning parameter
	/*
	
	//select outcome variables
	cvlasso ln_doc_vis `controls' i.site i.year, lse nfold(5) seed(1234) partial(i.site i.year) plotcv 
	local ln_doc_vis_selected `e(varXmodel)'
	
	//select treatment variables
	cvlasso zero_copay `controls' i.site i.year, lse nfold(5) seed(1234) partial(i.site i.year)
	local zero_copay_selected `e(varXmodel)'
	
	//run final regression with both sets of variables
	//not the most clean method since we end up with a lot of duplicates
	reghdfe ln_doc_vis zero_copay `ln_doc_vis_selected' `zero_copay_selected', vce(cluster zper) absorb(site year)
	
	