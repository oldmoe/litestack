# CAVEATS

This is a document that lists some caveats that you need to consider when dealing with Litestack and SQLite applications

## Single host (server) only

By design, SQLite can be accessed only (in a performant and safe way) from a single host machine. That means that you cannot have things like auto-scaling of app servers since there is but a single one of them. This app server can be a huge one, with many processes, but only one app server at a time.

## Containerization becomes a bit tricky

Container technology was originally designed for stateless applications. Based on this, one of the core aspects of containers is that they are immutable, deploying an app to container means destroying one container and creating another. With statefull applications, like database servers and similarly SQLite based applications, this will potentially mean a down time will be perceived, which in some approaches is mitigate but not perfectly (yet). Expect some quirks when dealing with SQLite and containers.

## Single writer / multi reader

In its default configuration, Litestack allows one writer at a time to write to the database file, while simultaneously allowing any number of readers to access the database. Generally SQLite is pretty fast in writes, but you should be aware that a long running write operation will prevent any other writers from proceeding, for example creating an index on a very large table will stop other writers until the index creation is finished. There is no concurrent index creation facility in SQLite, yet.

## Litestack does not release the GVL

This also applies to the Ruby SQLite3 gem, when it is performing a query, it will not allow any other threads in the Ruby process to resume until it returns. Care should be taken when writing low latency multi-threaded applications with Litestack, it is generally recommended to use fibers over threads in that case, since everything is serialized anyway it makes sense to avoid the ovreheads of mult-threaded environments

