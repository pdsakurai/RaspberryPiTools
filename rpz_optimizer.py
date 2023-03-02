import hashlib
import re
from urllib import request
from datetime import datetime, timedelta, timezone
from argparse import ArgumentParser
import tempfile
import os
import shutil
import typing


def get_arguments():
    arg_parser = ArgumentParser()
    arg_parser.add_argument("-s", "--source_url", required=True, type=str)
    arg_parser.add_argument("-d", "--destination_file", required=True, type=str)
    arg_parser.add_argument("-n", "--name_server", required=True, type=str)
    arg_parser.add_argument("-e", "--email_address", required=True, type=str)
    arg_parser.add_argument(
        "-t",
        "--type",
        type=str,
        choices=["domain", "host", "rpz non-wildcards only", "rpz wildcards only"],
        required=True,
    )
    args = arg_parser.parse_args()
    return (
        args.source_url,
        args.destination_file,
        args.name_server,
        args.email_address,
        args.type,
    )


def header_generator(
    source_url: str, primary_name_server: str, hostmaster_email_address: str
):
    yield f"; Source: {source_url}"

    today = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0)
    yield f"; Last modified: {today.isoformat()}"

    time_to_ = {
        "expire SOA": int(timedelta(hours=1).total_seconds()),
        "refresh": int(timedelta(days=1).total_seconds()),
        "retry": int(timedelta(minutes=1).total_seconds()),
        "expire": int(timedelta(days=30).total_seconds()),
        "expire NXDOMAIN cache": int(timedelta(seconds=30).total_seconds()),
    }

    yield ""

    yield f"$TTL {time_to_['expire SOA']}"

    hostmaster_email_address = hostmaster_email_address.replace(".", "/.").replace(
        "@", "."
    )
    yield f"@ IN SOA {primary_name_server}. {hostmaster_email_address}. ("
    yield f"         {today.strftime('%y%m%d%H%M')}"
    yield f"         {time_to_['refresh']}"
    yield f"         {time_to_['retry']}"
    yield f"         {time_to_['expire']}"
    yield f"         {time_to_['expire NXDOMAIN cache']} )"
    yield f" NS localhost."

    yield ""


def extract_domain_name(type_flag: str, next_coro: typing.Coroutine) -> typing.Coroutine:
    def create_domain_name_pattern() -> re.Pattern:
        if type_flag == "domain":
            return re.compile(r"^(?!#)(?P<domain_name>\S+)")
        if type_flag == "host":
            return re.compile(r"^(0.0.0.0)\s+(?!\1)(?P<domain_name>\S+)")
        if type_flag == "rpz non-wildcards only":
            return re.compile(
                r"^(?P<domain_name>(?=\w).+)(\s+CNAME\s+\.)", re.IGNORECASE
            )
        if type_flag == "rpz wildcards only":
            return re.compile(
                r"^(?P<domain_name>(?=\*\.).+)(\s+CNAME\s+\.)", re.IGNORECASE
            )
        raise Exception("Invalid type_flag")

    print(f"Extracting domain names using this format: {type_flag}")
    domain_name_pattern = create_domain_name_pattern()
    domain_names_extracted = 0
    try:
        while True:
            matches = domain_name_pattern.match((yield))
            if matches:
                domain_names_extracted += 1
                next_coro.send(matches["domain_name"])
    finally:
        print(f"Domain names extracted: {domain_names_extracted}")


def unique_filter(next_coro: typing.Coroutine) -> typing.Coroutine:
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
        print (f"Duplicates filtered out: {duplicates_count}")


def hasher(
    writer_coro: typing.Coroutine, next_coro: typing.Coroutine
) -> typing.Coroutine:
    hash = hashlib.md5()
    try:
        while True:
            line = yield
            hash.update(bytearray(line, "utf-8"))
            next_coro.send(line)
    finally:
        hash = f"md5: {hash.hexdigest()}"
        print(hash)
        writer_coro.send("")
        writer_coro.send(f"; {hash}")


def rpz_entry_formatter(next_coro: typing.Coroutine) -> typing.Coroutine:
    print("Formatting domain names to NX RPZ-compliant style: <domain name> CNAME .")
    while True:
        next_coro.send(f"{(yield)} CNAME .")


def writer(destination_file: str):
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
                            found_md5 = md5_pattern.match(line)
                            if found_md5:
                                return found_md5["hexdigest"]
                except OSError:
                    return None

            if get_md5(destination_file) != get_md5(temp_file_path):
                shutil.move(temp_file_path, destination_file)
                print(f"Temporary file moved to: {destination_file}")


class PipedCoroutines:
    def __init__(self, *commands):
        self.commands = commands

    def __enter__(self):
        for i in self.commands:
            next(i)

    def __exit__(self, *_):
        for i in self.commands:
            i.close()


if __name__ == "__main__":
    (
        flag_source_url,
        flag_destination_file,
        flag_name_server,
        flag_email_address,
        flag_type,
    ) = get_arguments()

    writer = writer(flag_destination_file)
    rpz_entry_formatter = rpz_entry_formatter(next_coro=writer)
    hasher = hasher(writer_coro=writer, next_coro=rpz_entry_formatter)
    unique_filter = unique_filter(next_coro=hasher)
    extract_domain_name = extract_domain_name(flag_type, next_coro=unique_filter)

    with PipedCoroutines(
        extract_domain_name, unique_filter, hasher, rpz_entry_formatter, writer
    ):
        for line in header_generator(
            flag_source_url, flag_name_server, flag_email_address
        ):
            writer.send(line)

        print(f"Downloading and processing file at: {flag_source_url}")
        with request.urlopen(flag_source_url) as src_file:
            for line in src_file:
                extract_domain_name.send(line.decode())


