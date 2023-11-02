## [Unreleased]

- Add similarity search support for Litesearch
- Enable similarity search for ActiveRecord and Sequel models
- Fix Litesearch tests
- Suppress chatty Litejob exit detector when there are no jobs in flight
- Tidy up the test folder

## [0.4.1] - 2023-10-11

- Add missing Litesearch::Model dependency

## [0.4.0] - 2023-10-11

- Introduced Litesearch, dynamic & fast full text search capability for Litedb
- ActiveRecord and Sequel integration for Litesearch
- Slight improvement to the Sequel Litedb adapter for better Litesearch integration

## [0.3.0] - 2023-08-13

- Reworked the Litecable thread safety model
- Fixed multiple litejob bugs (thanks Stephen Margheim)
- Fixed Railtie dependency (thanks Marco Roth)
- Litesupport fixes (thanks Stephen Margheim)
- Much improved metrics reporting for Litedb, Litecache, Litejob & Litecable
- Removed (for now, will come again later) litemetric reporting support for ad-hoc modules

## [0.2.6] - 2023-07-16

- Much improved database location setting (thanks Brad Gessler)
- A Rails generator for better Rails Litestack defaults (thanks Brad Gessler)
- Revamped Litemetric, now much faster and more accurate (still experimental)
- Introduced Liteboard, a dashboard for viewing Litemetric data

## [0.2.3] - 2023-05-20

- Cut back on options defined in the Litejob Rails adapter

## [0.2.2] - 2023-05-18

- Fix default queue location in Litejob


## [0.2.1] - 2023-05-08

- Fix a race condition in Litecable

## [0.2.0] - 2023-05-08

- Litecable, a SQLite driver for ActionCable
- Litemetric for metrics collection support (experimental, disabled by default)
- New schema for Litejob, old jobs are auto-migrated
- Code refactoring, extraction of SQL statements to external files
- Graceful shutdown support working properly
- Fork resilience

## [0.1.8] - 2023-03-08

- More code cleanups, more test coverage
- Retry support for jobs in Litejob
- Job storage and garbage collection for failed jobs
- Initial graceful shutdown support for Litejob (incomplete)
- More configuration options for Litejob

## [0.1.7] - 2023-03-05

- Code cleanup, removal of references to older name
- Fix for the litedb rake tasks (thanks: netmute)
- More fixes for the new concurrency model
- Introduced a logger for the Litejobqueue (doesn't work with Polyphony, fix should come soon)

## [0.1.6] - 2023-03-03

- Revamped the locking model, more robust, minimal performance hit
- Introduced a new resource pooling class
- Litecache and Litejob now use the resource pool
- Much less memory usage for Litecache and Litejob

## [0.1.0] - 2023-02-26

- Initial release
