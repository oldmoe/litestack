## [Unreleased]

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
