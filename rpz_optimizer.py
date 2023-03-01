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
    arg_parser.add_argument("-w", "--wildcards_only", action="store_true")
    args = arg_parser.parse_args()
    return (
        args.source_url,
        args.destination_file,
        args.name_server,
        args.email_address,
        args.wildcards_only,
    )

def header_generator(source_url : str, primary_name_server : str, hostmaster_email_address : str):
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
    
    hostmaster_email_address = hostmaster_email_address.replace(".", "/.").replace("@", ".")
    yield f"@ IN SOA {primary_name_server}. {hostmaster_email_address}. ("
    yield f"         {today.strftime('%y%m%d%H%M')}"
    yield f"         {time_to_['refresh']}"
    yield f"         {time_to_['retry']}"
    yield f"         {time_to_['expire']}"
    yield f"         {time_to_['expire NXDOMAIN cache']} )"
    yield f" NS localhost."

    yield ""

def downloader(source_url : str, next_cb : typing.Coroutine):
    with request.urlopen(source_url) as src_file:
        for line in src_file:
            next_cb.send(line.decode())
        next_cb.close()

def filter(wildcards_only : bool, next_cb : typing.Coroutine):
    regex = re.compile(r"^\*\.") if wildcards_only else re.compile(r"^\w")
    is_valid_rpz_trigger_rule = lambda entry: regex.match(entry)
    try:
        while True:
            line = (yield)
            if is_valid_rpz_trigger_rule(line):
                next_cb.send(line)
    except GeneratorExit:
        next_cb.close()

def linter(next_cb : typing.Coroutine):
    try:
        while True:
            line = (yield)
            next_cb.send(line.replace("\n", ""))
    except GeneratorExit:
        next_cb.close()


def writer(destination_file : str):
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_file_fd, temp_file_path = tempfile.mkstemp(text=True, dir=temp_dir)
        with os.fdopen(temp_file_fd, mode="w") as temp_file:
            try:
                while True:
                    line = (yield)
                    temp_file.write(f"{line}\n")
            except GeneratorExit:
                shutil.move(temp_file_path, destination_file)

if __name__ == "__main__":
    (
        source_url,
        destination_file,
        name_server,
        email_address,
        wildcards_only,
    ) = get_arguments()

    writer_ = writer(destination_file)
    next(writer_)
    linter_ = linter(writer_)
    next(linter_)
    filter_ = filter(wildcards_only, next_cb=linter_)
    next(filter_)

    for line in header_generator(source_url, name_server, email_address):
        writer_.send(line)
    downloader(source_url, filter_)


# def get_domain_name():
#     regex = re.compile(r"^(?P<domain>(?=\w|\*\.).+)(\s+CNAME\s+\.)", re.IGNORECASE)
#     def _impl(entry):
#         return regex.match(entry)["domain"]
#     return _impl
# get_domain_name = get_domain_name()
