* Add required packages from net

cap ado uninstall ftools
net install ftools, from("https://raw.githubusercontent.com/sergiocorreia/ftools/master/src/") replace

cap ado uninstall reghdfe
net install reghdfe, from("https://raw.githubusercontent.com/sergiocorreia/reghdfe/master/src/") replace

cap ado uninstall ivreg2
ssc install ivreg2, replace

cap ado uninstall ivreghdfe
net install ivreghdfe, from("https://raw.githubusercontent.com/sergiocorreia/ivreghdfe/master/src/") replace

* Add required packages from SSC
* require:  runtime dependency of recent reghdfe (fixes r(9) "reghdfe requires ... the require package")
* ranktest: dependency of ivreg2 / ivreghdfe
* distinct: used in 3_estimation/1_demand
local ssc_packages "estout binscatter unique coefplot require ranktest distinct"
if !missing("`ssc_packages'") {
    foreach pkg in `ssc_packages' {
        dis "Installing `pkg'"
        ssc install `pkg', replace
    }
}
