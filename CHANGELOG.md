# Change Log

## 2.1.0 (2017-05-15)

* Replace --print-constrained-cookbook-set with --print-trimmed-universe

## 2.0.3 (2017-05-12)

* Correctly print version if patch level was missing
* Only set DepSelector::Debug.log.level if DepSelector::Debug is defined
* Improve regex to avoid unwanted string replacement

## 2.0.2 (2017-05-11)

* Set DepSelector log level to INFO
* Add --print-constrained-cookbook-set option

## 2.0.1 (2017-05-02)

* Minor change to file name timestamp format

## 2.0.0 (2017-05-02)

* Set the node's environment to ensure accurate run_list expansion
* Add --capture option to capture all relevant information for local depsolver usage
* Add ability to use Chef DK's local depsolver to make calculations identical to a Chef Server
* Add --timeout option
* Add --csv-universe-to-json option for converting SQL captured cookbook universe to JSON
* Add --env-constraints-filter-universe option

## 1.0.1 (2016-03-17)

* Add error handling

## 1.0.0 (2016-03-17)

* Initial release
