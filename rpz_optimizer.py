import typing

from enum import StrEnum, auto
class SourceTypes(StrEnum):
    domain = auto()
    domain_as_wildcard = auto()
    host = auto()
    rpz_nonwildcard_only = auto()
    rpz_wildcard_only = auto()

class SourceTypesCategory(StrEnum):
    nonwildcard = auto()
    wildcard = auto()

source_types = {
    SourceTypesCategory.wildcard: [
        SourceTypes.domain_as_wildcard,
        SourceTypes.rpz_wildcard_only
    ],
    SourceTypesCategory.nonwildcard: [
        SourceTypes.domain,
        SourceTypes.host,
        SourceTypes.rpz_nonwildcard_only
    ]
}


rpz_actions = {
    "nodata": "CNAME .*",
    "nxdomain": "CNAME .",
    "null": "A 0.0.0.0"
}


def get_arguments():
    from argparse import ArgumentParser
    arg_parser = ArgumentParser()

    arg_characteristics = {"required": True, "type": str}
    arg_parser.add_argument("-n", "--name_server", **arg_characteristics)
    arg_parser.add_argument("-e", "--email_address", **arg_characteristics)

    arg_characteristics.setdefault("action", "append")
    arg_parser.add_argument("-d", "--destination_file", **arg_characteristics)
    arg_parser.add_argument("-a", "--rpz_action", **arg_characteristics, choices=list(rpz_actions.keys()))

    arg_parser.add_argument("-s", "--source_url", **arg_characteristics)
    arg_parser.add_argument(
        "-t",
        "--source_type",
        **arg_characteristics,
        choices=[item for array in source_types.values() for item in array],
    )

    args = arg_parser.parse_args()

    if len(args.destination_file) != len(args.rpz_action):
        raise Exception("Must have the same number of args for -d and -a")

    if len(args.source_url) != len(args.source_type):
        raise Exception("Must have the same number of args for -s and -t")

    return args


def header_generator(
    source_url: typing.Sequence[str],
    primary_name_server: str,
    hostmaster_email_address: str,
) -> typing.Generator[str, None, None]:
    from datetime import datetime, timedelta, timezone
    tz_manila = timezone(timedelta(hours=8))
    today = datetime.now(tz_manila).replace(microsecond=0)
    yield f"; Last modified: {today.isoformat()}"

    for n, x in enumerate(source_url, 1):
        yield f"; Source #{n}: {x}"

    to_seconds = lambda **kwargs: int(timedelta(**kwargs).total_seconds())
    time_to_ = {
        "expire SOA": to_seconds(hours=1),
        "refresh": to_seconds(hours=23),
        "retry": to_seconds(minutes=1),
        "expire": to_seconds(days=30),
        "expire NXDOMAIN cache": to_seconds(seconds=30),
    }

    yield ""

    yield f"$TTL {time_to_['expire SOA']}"

    hostmaster_email_address = hostmaster_email_address.replace(".", "/.").replace(
        "@", "."
    )
    yield (
        f"@ IN SOA"
        f" {primary_name_server}."
        f" {hostmaster_email_address}."
        f" {today.strftime('%y%m%d%H%M')}"
        f" {time_to_['refresh']}"
        f" {time_to_['retry']}"
        f" {time_to_['expire']}"
        f" {time_to_['expire NXDOMAIN cache']}"
    )

    yield f" IN NS localhost."

    yield ""


def extract_domain_name(
    source_type: SourceTypes,
    next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    def create_domain_name_pattern():
        from re import compile, IGNORECASE
        match (source_type):
            case SourceTypes.domain | SourceTypes.domain_as_wildcard:
                return compile(r"^(?!#)(?P<domain_name>\S+)")
            case SourceTypes.host:
                return compile(r"^(0.0.0.0)\s+(?!\1)(?P<domain_name>\S+)")
            case SourceTypes.rpz_nonwildcard_only:
                return compile(r"^(?P<domain_name>(?=\w).+)(\s+CNAME\s+\.)", IGNORECASE)
            case SourceTypes.rpz_wildcard_only:
                return compile(r"^(?P<domain_name>(?=\*\.).+)(\s+CNAME\s+\.)", IGNORECASE)

    try:
        domain_name_pattern = create_domain_name_pattern()
        domain_names_extracted = 0
        while True:
            if matches := domain_name_pattern.match((yield)):
                domain_names_extracted += 1
                next_coro.send(matches["domain_name"].removeprefix("*."))

    finally:
        print(f'Domain names extracted from "{source_type}"-formatted source: {domain_names_extracted:,}')


def wildcard_miss_filter(
    database: typing.Sequence[str],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    try:
        duplicates_count = 0
        while True:
            line = (yield)
            parent = line.split(".")
            has_hit = False

            while len(parent := parent[1:]) >= 2 and not (has_hit:= ".".join(parent) in database):
                pass

            if has_hit:
                duplicates_count += 1
            else:
                next_coro.send(line)
    finally:
        print(f"Wildcard hits filtered out: {duplicates_count:,}")


def unique_filter(
    *,
    what_are_filtered_out: str = None,
    database: typing.Sequence[str] = [],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any] = None
) -> typing.Coroutine[None, str, None]:
    try:
        duplicates_count = 0
        while True:
            if (line := (yield)) not in database:
                database.append(line)
                if next_coro:
                    next_coro.send(line)
            else:
                duplicates_count += 1
    finally:
        if what_are_filtered_out:
            print(f"Duplicate {what_are_filtered_out} filtered out: {duplicates_count:,}")


def hasher(
    rpz_formatter_coros: typing.Sequence[typing.Coroutine[typing.Any, str, typing.Any]],
    writer_coros: typing.Sequence[typing.Coroutine[typing.Any, str, typing.Any]]
) -> typing.Coroutine[None, str, None]:
    try:
        from hashlib import md5
        hash = md5()
        rpz_entry_counts = 0
        while True:
            line = yield
            hash.update(line.encode("utf-8"))
            rpz_entry_counts += 1
            for x in rpz_formatter_coros:
                x.send(line)
    finally:
        hash = f"RPZ entries ({rpz_entry_counts:,}) md5sum: {hash.hexdigest()}"
        print(hash)
        for x in writer_coros:
            x.send("")
            x.send(f"; {hash}")


def rpz_entry_formatter(
    rpz_action: str,
    next_coro: typing.Coroutine[typing.Any, str, typing.Any],
) -> typing.Coroutine[None, str, None]:
    while True:
        next_coro.send(f"{(yield)} {rpz_action}")


def writer(
    destination_file: str
) -> typing.Coroutine[None, str, None]:
    from tempfile import mkstemp
    temp_file_fd, temp_file_path = mkstemp()
    print(f"Temporary file created: {temp_file_path}")

    cached_lines = []
    def flush_cached_lines(file:typing.TextIO) -> None:
        file.writelines(cached_lines)
        cached_lines.clear()

    try:
        from os import fdopen
        with fdopen(temp_file_fd, mode="w") as temp_file:
            cached_lines_max_count = 50000
            while True:
                cached_lines.append(f'{(yield)}\n')
                if len(cached_lines) == cached_lines_max_count:
                    flush_cached_lines(temp_file)
    finally:
        if cached_lines:
            with open(temp_file_path, mode="a") as temp_file:
                flush_cached_lines(temp_file)

        def get_md5() -> typing.Callable[[str], str]:
            def reverse_readline(
                file_path:str
            ) -> typing.Generator[str, None, None]:
                with open(file_path) as file:
                    from os import SEEK_END
                    first_line = file.readline()
                    index = file.seek(0, SEEK_END)
                    length = 0
                    while (index := index - 1) > 0:
                        if file.read(1) == "\n" and length > 1:
                            yield file.readline()
                            length = 0
                        from os import SEEK_SET
                        file.seek(index, SEEK_SET)
                        length += 1
                yield first_line
            from re import compile
            md5_pattern = compile(r"md5sum:\s(?P<hexdigest>\w{32})")
            def _impl(
                file_path: str
            ) -> str:
                for line in reverse_readline(file_path):
                    if found_md5 := md5_pattern.search(line):
                        return found_md5["hexdigest"]
            return _impl
        get_md5 = get_md5()

        if get_md5(destination_file) != get_md5(temp_file_path):
            from shutil import move
            move(temp_file_path, destination_file)
            print(f"Temporary file moved to: {destination_file}")
        else:
            print("Nothing changed; Deleting temporary file")


class PipedCoroutines:
    def __init__(self, *commands):
        self.commands = commands

    def __enter__(self):
        for i in self.commands:
            next(i)

    def __exit__(self, *_):
        for i in self.commands:
            i.close()


def downloader(
    url: str,
    source_type: SourceTypes,
    extractor: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, typing.Any, None]:
    try:
        from urllib import request
        with request.urlopen(url) as src_file:
            print(f'Processing "{source_type}"-formatted source: {url}')
            for line in src_file:
                (yield)
                extractor.send(line.decode())
            print(f"Done processing: {url}")
    except request.URLError:
        print(f'Cannot process "{source_type}"-formatted source: {url}')


def collect_wildcard_domains(
    sources : typing.Sequence[typing.Tuple[str, SourceTypes]]
) -> typing.Sequence[str]:
    database_1stpass = []
    collector_coro = unique_filter(database=database_1stpass)
    filter_coro = wildcard_miss_filter(database_1stpass, next_coro = collector_coro)
    extractor_coros = {
        type : extract_domain_name(type, next_coro = filter_coro)
        for _, type in sources
    }

    with PipedCoroutines(
        *extractor_coros.values(), filter_coro, collector_coro
    ):
        start_downloading(sources, extractor_coros)

    database_2ndpass = []
    collector_coro = unique_filter(database=database_2ndpass)
    filter_coro = wildcard_miss_filter(database_1stpass, next_coro = collector_coro)

    with PipedCoroutines(
        collector_coro, filter_coro
    ):
        for x in database_1stpass:
            filter_coro.send(x)

    print(f"Wildcard domains collected: {len(database_2ndpass):,}")
    return database_2ndpass


def start_downloading(
    sources : typing.Sequence[typing.Tuple[str, SourceTypes]],
    extractors : typing.Dict[SourceTypes,typing.Coroutine[None, str, None]]
) -> None:
    from collections import deque
    downloaders = deque(
        (
            downloader(url, type, extractors[type])
            for url, type in sources
        )
    )

    while downloaders:
        item = downloaders.popleft()
        try:
            item.send(None)
        except StopIteration:
            pass
        else:
            downloaders.append(item)


if __name__ == "__main__":
    args = get_arguments()

    coroutines = []

    writers = []
    rpz_entry_formatters = []
    for destination_file, rpz_action in zip(args.destination_file, args.rpz_action):
        x = writer(destination_file)
        writers.append(x)
        rpz_entry_formatters.append(rpz_entry_formatter(rpz_actions[rpz_action], next_coro=x))
    coroutines.extend(writers)
    coroutines.extend(rpz_entry_formatters)

    next_coroutine = hasher = hasher(writer_coros=writers, rpz_formatter_coros=rpz_entry_formatters)
    coroutines.append(next_coroutine)

    next_coroutine = collector = unique_filter(next_coro=next_coroutine, what_are_filtered_out="domains")
    coroutines.append(next_coroutine)

    wildcard_domains = []
    sources = list(zip(args.source_url, args.source_type))
    if wildcard_sources := [
        (url,type) 
        for url, type in sources
        if type in source_types[SourceTypesCategory.wildcard]
    ]:
        wildcard_domains = collect_wildcard_domains(wildcard_sources)
        next_coroutine = wildcard_miss_filter(wildcard_domains, next_coro=next_coroutine)
        coroutines.append(next_coroutine)
        wildcard_sources = []

    sources = [
        (url,type)
        for url, type in sources 
        if type in source_types[SourceTypesCategory.nonwildcard]
    ]
    extractors = {
        type: extract_domain_name(type, next_coro=next_coroutine)
        for _, type in sources
    }
    coroutines.extend(extractors.values())

    coroutines.reverse()
    with PipedCoroutines(*coroutines):
        for line in header_generator(
            args.source_url, args.name_server, args.email_address
        ):
            for x in writers:
                x.send(line)

        for x in wildcard_domains:
            collector.send(f'{x}')
            hasher.send(f'*.{x}')

        start_downloading(sources, extractors)
