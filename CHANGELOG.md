## [Unreleased]

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.4.3...master)
- Fix a table not defined bug for Litesearch
- Add conditional mapping of external fields to Litesearch (backed index)
- As a consequence of the above, support AR polymorphic associations
- As a consequence of the above, support indexing and searching for ActionText attributes
- Remove 'hanami-router' as a dependency, rely on vanilla Rack for Liteboard 

## [0.4.3] - 2024-02-15

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.4.2...v0.4.3)
- Add "sequel" as a development dependency
- Diff links in CHANGELOG (thanks Weston Ganger)
- Fix daemonize type in liteboard (thanks Julian Rubisch)
- Better Litecache schema (streamlined numeric value support)
- Support for set_multi and get_multi in Litecache (read_multi and write_multi support for Rails Cache store)
- More tests written for Litecache and Rails Litecache store
- Experimenting with removing the Rails LocalCache as it doesn't show enough improvement in performance to compensate for the memory overhead
- Switch Litecache to a FIFO eviction model vs LRU (thanks Julian Rubisch and Stephen Margheim)

## [0.4.2] - 2023-11-11

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.4.1...v0.4.2)
- Add similarity search support for Litesearch (works best for non-trigram indexes)
- Enable similarity search for ActiveRecord and Sequel models
- Fix Litesearch tests
- Suppress chatty Litejob exit detector when there are no jobs in flight
- Tidy up the test folder
- [#41](https://github.com/oldmoe/litestack/pull/41) - Fix bug in Litecable where the `connected` event was not getting propagated
- Add Litemetric and Liteboard info to README.doc
- Fix the testing rake task

## [0.4.1] - 2023-10-11

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.4.0...v0.4.1)
- Add missing Litesearch::Model dependency

## [0.4.0] - 2023-10-11

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.3.0...v0.4.0)
- Introduced Litesearch, dynamic & fast full text search capability for Litedb
- ActiveRecord and Sequel integration for Litesearch
- Slight improvement to the Sequel Litedb adapter for better Litesearch integration

## [0.3.0] - 2023-08-13

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.2.6...v0.3.0)
- Reworked the Litecable thread safety model
- Fixed multiple litejob bugs (thanks Stephen Margheim)
- Fixed Railtie dependency (thanks Marco Roth)
- Litesupport fixes (thanks Stephen Margheim)
- Much improved metrics reporting for Litedb, Litecache, Litejob & Litecable
- Removed (for now, will come again later) litemetric reporting support for ad-hoc modules

## [0.2.6] - 2023-07-16

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.2.3...v0.2.6)
- Much improved database location setting (thanks Brad Gessler)
- A Rails generator for better Rails Litestack defaults (thanks Brad Gessler)
- Revamped Litemetric, now much faster and more accurate (still experimental)
- Introduced Liteboard, a dashboard for viewing Litemetric data

## [0.2.3] - 2023-05-20

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.2.2...v0.2.3)
- Cut back on options defined in the Litejob Rails adapter

## [0.2.2] - 2023-05-18

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.2.1...v0.2.2)
- Fix default queue location in Litejob


## [0.2.1] - 2023-05-08

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.2.0...v0.2.1)
- Fix a race condition in Litecable

## [0.2.0] - 2023-05-08

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.1.8...v0.2.0)
- Litecable, a SQLite driver for ActionCable
- Litemetric for metrics collection support (experimental, disabled by default)
- New schema for Litejob, old jobs are auto-migrated
- Code refactoring, extraction of SQL statements to external files
- Graceful shutdown support working properly
- Fork resilience

## [0.1.8] - 2023-03-08

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.1.7...v0.1.8)
- More code cleanups, more test coverage
- Retry support for jobs in Litejob
- Job storage and garbage collection for failed jobs
- Initial graceful shutdown support for Litejob (incomplete)
- More configuration options for Litejob

## [0.1.7] - 2023-03-05

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.1.6...v0.1.7)
- Code cleanup, removal of references to older name
- Fix for the litedb rake tasks (thanks: netmute)
- More fixes for the new concurrency model
- Introduced a logger for the Litejobqueue (doesn't work with Polyphony, fix should come soon)

## [0.1.6] - 2023-03-03

- [View Diff](https://github.com/oldmoe/litestack/compare/v0.1.0...v0.1.6)
- Revamped the locking model, more robust, minimal performance hit
- Introduced a new resource pooling class
- Litecache and Litejob now use the resource pool
- Much less memory usage for Litecache and Litejob

## [0.1.0] - 2023-02-26

- Initial release
