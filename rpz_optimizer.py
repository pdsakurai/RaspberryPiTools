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
        "refresh": to_seconds(hours=12),
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
            if (match := domain_name_pattern.match((yield))) \
                and (match := match["domain_name"]) \
                and not match.endswith("."):
                domain_names_extracted += 1
                next_coro.send(match.removeprefix("*."))

    finally:
        print(f'Extracted domains from "{source_type}"-formatted source: {domain_names_extracted:,}')


def wildcard_miss_filter_impl(database, is_line_a_nonwildcard, line):
    parent = line.split(".") if is_line_a_nonwildcard else line.split(".")[1:]
    has_hit = False
    while not (has_hit:= ".".join(parent) in database) and len(parent := parent[1:]) >= 2:
        pass
    return None if has_hit else line


def wildcard_miss_filter(
    *,
    are_inputs_nonwildcard = False,
    database: typing.Sequence[str],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    from multiprocessing import pool
    cpu_count = 4 # Use case: RPi 3B+
    with pool.Pool(cpu_count) as pool:
        task_share = 333
        cached_lines_max = cpu_count * task_share
        cached_lines = []
        results = []

        def forward_results():
            while results:
                generator = results.pop()
                for missed_line in generator:
                    if missed_line:
                        next_coro.send(missed_line)

        def distribute_tasks():
            from functools import partial
            from math import ceil
            results.append(
                pool.imap(
                    func=partial(wildcard_miss_filter_impl, database, are_inputs_nonwildcard), 
                    iterable=cached_lines.copy(), 
                    chunksize=ceil(len(cached_lines)/cpu_count)))
            cached_lines.clear()

        try:
            while True:
                cached_lines.append((yield))
                if len(cached_lines) == cached_lines_max:
                    forward_results()
                    distribute_tasks()
        finally:
            if cached_lines:
                distribute_tasks()
            forward_results()


def unique_filter(
    *,
    what_are_filtered: str = None,
    database: typing.Sequence[str],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    try:
        while True:
            if (line := (yield)) not in database:
                next_coro.send(line)
    finally:
        if what_are_filtered:
            print(f"Filtered {what_are_filtered} domains: {len(database):,}")


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
    *,
    destination_file: str,
    processing_duration : typing.Callable[[None], str] = None
) -> typing.Coroutine[None, str, None]:
    from tempfile import TemporaryDirectory, mkstemp
    with TemporaryDirectory() as temp_dir:
        temp_file_fd, temp_file_path = mkstemp(dir=temp_dir, text=True)

        try:
            with open(temp_file_fd, mode="w") as temp_file:
                while True:
                    temp_file.write(f'{(yield)}\n')

        finally:
            if processing_duration:
                with open(temp_file_path, mode="a") as temp_file:
                    processing_duration = processing_duration()
                    print(processing_duration)
                    temp_file.write(f"; {processing_duration}")

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
                print(f"Updated: {destination_file}")


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
    log = f"\"{source_type}\"-formatted source: {url}"
    try:
        from urllib import request
        with request.urlopen(url, timeout=15) as src_file:
            for line in src_file:
                (yield)
                extractor.send(line.decode())
            print(f"Downloaded {log}")
    except request.URLError:
        print(f'Cannot download {log}')
        print("Aborting operation...")
        exit(1)


def sink(
    database: typing.Sequence[str],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any] = None
) -> typing.Coroutine[None, typing.Any, None]:
    try:
        while True:
            line = (yield)
            database.append(line)
            if next_coro:
                next_coro.send(line)
    finally:
        pass


def collect_wildcard_domains(
    sources : typing.Sequence[typing.Tuple[str, SourceTypes]]
) -> typing.Sequence[str]:
    database_1stpass = []
    sink_coro = sink(database_1stpass)
    unique_filter_coro = unique_filter(database=database_1stpass, next_coro=sink_coro)
    wildcard_filter_coro = wildcard_miss_filter(database=database_1stpass, next_coro = unique_filter_coro)
    extractor_coros = {
        type : extract_domain_name(type, next_coro = wildcard_filter_coro)
        for _, type in sources
    }

    with PipedCoroutines(
        *extractor_coros.values(), wildcard_filter_coro, unique_filter_coro, sink_coro
    ):
        start_downloading(sources, extractor_coros)

    database_2ndpass = []
    sink_coro = sink(database_2ndpass)
    wildcard_filter_coro = wildcard_miss_filter(database=database_1stpass, next_coro = sink_coro)

    with PipedCoroutines(
        wildcard_filter_coro, sink_coro
    ):
        while database_1stpass:
            wildcard_filter_coro.send(database_1stpass.pop())

    print(f"Filtered wildcard domains: {len(database_2ndpass)}")
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
    def get_processing_duration() -> typing.Callable[[None],str]:
        from datetime import datetime
        start = datetime.now()
        return lambda : f"Processed in: {datetime.now() - start}"
    get_processing_duration = get_processing_duration()

    args = get_arguments()

    coroutines = []

    writers = []
    rpz_entry_formatters = []
    for d, rpz_action in zip(args.destination_file, args.rpz_action):
        x = writer(destination_file=d, processing_duration=get_processing_duration)
        writers.append(x)
        rpz_entry_formatters.append(rpz_entry_formatter(rpz_actions[rpz_action], next_coro=x))
    coroutines.extend(writers)
    coroutines.extend(rpz_entry_formatters)

    next_coroutine = hasher = hasher(writer_coros=writers, rpz_formatter_coros=rpz_entry_formatters)
    coroutines.append(next_coroutine)

    unique_domains = []
    next_coroutine = sink_coro = sink(database=unique_domains, next_coro=next_coroutine)
    coroutines.append(next_coroutine)

    next_coroutine = unique_filter(database=unique_domains, next_coro=next_coroutine, what_are_filtered="non-wildcard")
    coroutines.append(next_coroutine)

    wildcard_domains = []
    sources = list(zip(args.source_url, args.source_type))
    if wildcard_sources := [
        (url,type) 
        for url, type in sources
        if type in source_types[SourceTypesCategory.wildcard]
    ]:
        wildcard_domains = collect_wildcard_domains(wildcard_sources)
        next_coroutine = wildcard_miss_filter(are_inputs_nonwildcard=True, database=wildcard_domains, next_coro=next_coroutine)
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

    with PipedCoroutines(*reversed(coroutines)):
        for line in header_generator(
            args.source_url, args.name_server, args.email_address
        ):
            for x in writers:
                x.send(line)

        for x in wildcard_domains:
            hasher.send(f'{x}')
            for y in rpz_entry_formatters:
                y.send(f'*.{x}')

        start_downloading(sources, extractors)
