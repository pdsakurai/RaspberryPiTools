from collections import deque
import hashlib
import re
from urllib import request
from datetime import datetime, timedelta, timezone
import argparse
import tempfile
import os
import shutil
import typing


def get_arguments() -> argparse.Namespace:
    arg_parser = argparse.ArgumentParser()

    arg_characteristics = {"required": True, "type": str}
    arg_parser.add_argument("-n", "--name_server", **arg_characteristics)
    arg_parser.add_argument("-e", "--email_address", **arg_characteristics)
    arg_parser.add_argument("-d", "--destination_file", **arg_characteristics)

    arg_characteristics.setdefault("action", "append")
    arg_parser.add_argument("-s", "--source_url", **arg_characteristics)
    arg_parser.add_argument(
        "-t",
        "--source_type",
        **arg_characteristics,
        choices=["domain", "host", "rpz non-wildcard only", "rpz wildcard only"],
    )

    args = arg_parser.parse_args()

    if len(args.source_url) != len(args.source_type):
        raise "Must have the same number of args for -s and -t"

    return args


def header_generator(
    source_url: typing.Sequence[str],
    primary_name_server: str,
    hostmaster_email_address: str,
) -> typing.Generator[str, None, None]:
    tz_manila = timezone(timedelta(hours=8))
    today = datetime.now(tz_manila).replace(microsecond=0)
    yield f"; Last modified: {today.isoformat()}"

    for n, x in enumerate(source_url, 1):
        yield f"; Source #{n}: {x}"

    to_seconds = lambda **kwargs: int(timedelta(**kwargs).total_seconds())
    time_to_ = {
        "expire SOA": to_seconds(hours=1),
        "refresh": to_seconds(days=1),
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
    source_type: str, next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    def create_domain_name_pattern() -> re.Pattern:
        if source_type == "domain":
            return re.compile(r"^(?!#)(?P<domain_name>\S+)")
        if source_type == "host":
            return re.compile(r"^(0.0.0.0)\s+(?!\1)(?P<domain_name>\S+)")
        if source_type == "rpz non-wildcard only":
            return re.compile(
                r"^(?P<domain_name>(?=\w).+)(\s+CNAME\s+\.)", re.IGNORECASE
            )
        if source_type == "rpz wildcard only":
            return re.compile(
                r"^(?P<domain_name>(?=\*\.).+)(\s+CNAME\s+\.)", re.IGNORECASE
            )
        raise Exception(f"Invalid source_type: {source_type}")

    domain_name_pattern = create_domain_name_pattern()
    domain_names_extracted = 0
    try:
        while True:
            if matches := domain_name_pattern.match((yield)):
                domain_names_extracted += 1
                next_coro.send(matches["domain_name"])
    finally:
        print(
            f'Domain names extracted from "{source_type}"-formatted source: {domain_names_extracted:,}'
        )


def unique_filter(
    next_coro: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, str, None]:
    unique_domain_names = set()
    duplicates_count = 0
    try:
        while True:
            line = yield
            if line not in unique_domain_names:
                unique_domain_names.add(line)
                next_coro.send(line)
            else:
                duplicates_count += 1
    finally:
        print(f"Duplicates filtered out: {duplicates_count:,}")


def hasher(
    writer_coro: typing.Coroutine[typing.Any, str, typing.Any],
    next_coro: typing.Coroutine[typing.Any, str, typing.Any],
) -> typing.Coroutine[None, str, None]:
    hash = hashlib.md5()
    try:
        while True:
            line = yield
            hash.update(line.encode("utf-8"))
            next_coro.send(line)
    finally:
        hash = f"md5: {hash.hexdigest()}"
        print(f"RPZ entries' {hash}")
        writer_coro.send("")
        writer_coro.send(f"; {hash}")


def rpz_entry_formatter(
    next_coro: typing.Coroutine[typing.Any, str, typing.Any],
) -> typing.Coroutine[None, str, None]:
    formatted_counts = 0
    try:
        while True:
            next_coro.send(f"{(yield)} CNAME .")
            formatted_counts += 1
    finally:
        print(f"RPZ-formatted entries: {formatted_counts:,}")


def writer(destination_file: str) -> typing.Coroutine[None, str, None]:
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_file_fd, temp_file_path = tempfile.mkstemp(dir=temp_dir)
        print(f"Temporary file created: {temp_file_path}")
        try:
            with os.fdopen(temp_file_fd, mode="w") as temp_file:
                while True:
                    temp_file.write(f"{(yield)}\n")
        finally:
            md5_pattern = re.compile(r"^;\smd5:\s(?P<hexdigest>\w+)")

            def get_md5(file_path: str) -> str:
                try:
                    with open(file_path) as file:
                        for line in file:
                            if found_md5 := md5_pattern.match(line):
                                return found_md5["hexdigest"]
                except OSError:
                    return None

            if get_md5(destination_file) != get_md5(temp_file_path):
                shutil.move(temp_file_path, destination_file)
                print(f"Temporary file moved to: {destination_file}")
            else:
                print("Nothing changed; Deleting created temporary file")


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
    url: str, type: str, extractor: typing.Coroutine[typing.Any, str, typing.Any]
) -> typing.Coroutine[None, typing.Any, None]:
    try:
        with request.urlopen(url) as src_file:
            print(f'Processing "{type}"-formatted source: {url}')
            for line in src_file:
                (yield)
                extractor.send(line.decode())
            print(f"Done processing: {url}")
    except request.URLError:
        print(f'Cannot process "{type}"-formatted source: {url}')


if __name__ == "__main__":
    args = get_arguments()

    writer = writer(args.destination_file)
    rpz_entry_formatter = rpz_entry_formatter(next_coro=writer)
    hasher = hasher(writer_coro=writer, next_coro=rpz_entry_formatter)
    unique_filter = unique_filter(next_coro=hasher)
    extractors = {
        x: extract_domain_name(x, next_coro=unique_filter)
        for x in set(args.source_type)
    }

    with PipedCoroutines(
        *extractors.values(), unique_filter, hasher, rpz_entry_formatter, writer
    ):
        for line in header_generator(
            args.source_url, args.name_server, args.email_address
        ):
            writer.send(line)

        downloaders = deque(
            (
                downloader(source, type, extractors[type])
                for source, type in zip(args.source_url, args.source_type)
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
