/*******************************************************************************
link_diagnostics.do

Can the four IQVIA extracts be linked at the firm level, or do IQVIA's firm-
name restatements (M&A) break the panel at extract boundaries?

Boundary transitions: 2008q4->2009q1, 2010q4->2011q1, 2016q4->2017q1.
Comparison group: the same seasonal transition (Q4->Q1) within extracts.

Diagnostics:
 1. Exit/entry rates of corporation-molecule-strength cells by quarter.
    If names break, apparent exits (and matching entries) spike at boundaries.
 2. Same at corporation-molecule level, generics only.
 3. Molecule coverage per quarter (universe differences across extracts).
 4. Molecule-quarter level: number of generic firms and average generic
    price; check whether within-molecule changes jump at boundaries.

Input:  ../input/1_clean_prices/output_local/iqvia_panel_2004_2019.dta
Output: log only (diagnostic)
*******************************************************************************/

version 18
clear all
set more off

local IN "../input/1_clean_prices/output_local"

*==============================================================================
* 1. Corporation-molecule-strength cell continuity
*==============================================================================
use "`IN'/iqvia_panel_2004_2019.dta", clear
collapse (sum) su rev_usd, by(corporation molecule strength qdate)
drop if su <= 0

egen long cell = group(corporation molecule strength)
sort cell qdate
by cell: gen byte exit  = (_n == _N) | (qdate[_n+1] != qdate + 1)
by cell: gen byte entry = (_n == 1)  | (qdate[_n-1] != qdate - 1)

preserve
    drop if qdate == tq(2019q4)
    collapse (mean) exit (count) ncells=exit, by(qdate)
    gen byte q4       = quarter(dofq(qdate)) == 4
    gen byte boundary = inlist(qdate, tq(2008q4), tq(2010q4), tq(2016q4))
    di as result _n "=== 1. Firm-molecule-strength EXIT rate, all Q4->Q1 transitions ==="
    list qdate exit ncells boundary if q4, noobs sep(0)
    di as result "boundary Q4s vs non-boundary Q4s vs all other quarters:"
    sum exit if boundary
    sum exit if q4 & !boundary
    sum exit if !boundary
restore

preserve
    drop if qdate == tq(2004q1)
    collapse (mean) entry (count) ncells=entry, by(qdate)
    gen byte q1       = quarter(dofq(qdate)) == 1
    gen byte boundary = inlist(qdate, tq(2009q1), tq(2011q1), tq(2017q1))
    di as result _n "=== 1b. Firm-molecule-strength ENTRY rate, all Q1s ==="
    list qdate entry ncells boundary if q1, noobs sep(0)
    sum entry if boundary
    sum entry if q1 & !boundary
restore

*==============================================================================
* 2. Corporation-molecule continuity, generics only
*==============================================================================
use "`IN'/iqvia_panel_2004_2019.dta", clear
keep if branded == 0
collapse (sum) su rev_usd, by(corporation molecule qdate)
drop if su <= 0

egen long cell = group(corporation molecule)
sort cell qdate
by cell: gen byte exit  = (_n == _N) | (qdate[_n+1] != qdate + 1)
by cell: gen byte entry = (_n == 1)  | (qdate[_n-1] != qdate - 1)

preserve
    drop if qdate == tq(2019q4)
    collapse (mean) exit (count) ncells=exit, by(qdate)
    gen byte q4       = quarter(dofq(qdate)) == 4
    gen byte boundary = inlist(qdate, tq(2008q4), tq(2010q4), tq(2016q4))
    di as result _n "=== 2. GENERIC firm-molecule EXIT rate, all Q4->Q1 transitions ==="
    list qdate exit ncells boundary if q4, noobs sep(0)
    sum exit if boundary
    sum exit if q4 & !boundary
restore

*==============================================================================
* 3. Molecule coverage per quarter (extract universe differences)
*==============================================================================
use "`IN'/iqvia_panel_2004_2019.dta", clear
drop if su <= 0
egen byte moltag = tag(molecule qdate)
preserve
    collapse (sum) nmol=moltag, by(qdate)
    di as result _n "=== 3. Number of distinct molecules per quarter ==="
    list qdate nmol, noobs sep(4)
restore

*==============================================================================
* 4. Molecule-quarter generic firm counts and average prices
*==============================================================================
use "`IN'/iqvia_panel_2004_2019.dta", clear
drop if su <= 0
egen byte gfirm = tag(molecule qdate corporation) if branded == 0
gen double su_g  = su      if branded == 0
gen double rev_g = rev_usd if branded == 0
collapse (sum) n_gen=gfirm su_g rev_g, by(molecule qdate)
gen double p_gen = rev_g / su_g

egen long molid = group(molecule)
xtset molid qdate
gen dn  = n_gen - L.n_gen
gen byte anych = dn != 0                  if !missing(dn)
gen dlp = ln(p_gen) - ln(L.p_gen)

preserve
    collapse (mean) dn anych dlp (count) nmol=dn, by(qdate)
    gen byte q1       = quarter(dofq(qdate)) == 1
    gen byte boundary = inlist(qdate, tq(2009q1), tq(2011q1), tq(2017q1))
    di as result _n "=== 4. Within-molecule change in # generic firms and log generic price ==="
    di as result "(dn = mean change in generic firm count; anych = share of molecules"
    di as result " with any change; dlp = mean change in log avg generic price)"
    list qdate dn anych dlp nmol boundary if q1, noobs sep(0)
    di as result "boundary Q1s:"
    sum dn anych dlp if boundary
    di as result "non-boundary Q1s:"
    sum dn anych dlp if q1 & !boundary
    di as result "all non-boundary quarters:"
    sum dn anych dlp if !boundary
restore
