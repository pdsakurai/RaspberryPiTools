import re
from urllib import request
from datetime import datetime, timedelta, timezone
from argparse import ArgumentParser

def generate_zone_file_header(source):
    yield f"; Source: {source}\n"

    today = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0)
    yield f"; Last modified: {today.isoformat()}\n\n"

    time_to_ = {
        "refresh" : int(timedelta(days=1).total_seconds()),
        "retry" : int(timedelta(minutes=1).total_seconds()),
        "expire" : int(timedelta(days=30).total_seconds()),
        "expire NXDOMAIN cache": int(timedelta(seconds=30).total_seconds()),
        "expire SOA": int(timedelta(hours=1).total_seconds()),
    }

    yield f"$TTL {time_to_['expire SOA']}\n"
    yield f"@ IN SOA storage.capri. pdsakurai/.gmail.com. (\n"
    yield f"         {today.strftime('%y%m%d%H%M')}\n"
    yield f"         {time_to_['refresh']}\n"
    yield f"         {time_to_['retry']}\n"
    yield f"         {time_to_['expire']}\n"
    yield f"         {time_to_['expire NXDOMAIN cache']} )\n"
    yield f" NS localhost.\n\n"

arg_parser = ArgumentParser()
arg_parser.add_argument("-s", "--source_url", nargs=1, required=True, type=str)
arg_parser.add_argument("-d", "--destination_file", nargs=1, required=True, type=str)
args = arg_parser.parse_args()

source_url=args.source_url[0]
destination_file=args.destination_file[0]

with request.urlopen(source_url) as src_file:
    with open(destination_file, mode="w") as dest_file:
        dest_file.writelines(generate_zone_file_header(source_url))

        decoded_lines = (line_in_binary.decode() for line_in_binary in src_file)
        def is_valid_rpz_trigger_rule():
            regex = re.compile(r"^\w")
            return lambda entry : regex.match(entry)
        is_valid_rpz_trigger_rule = is_valid_rpz_trigger_rule()
        dest_file.writelines(line for line in decoded_lines if is_valid_rpz_trigger_rule(line))

# def get_domain_name():
#     regex = re.compile(r"^(?P<domain>(?=\w|\*\.).+)(\s+CNAME\s+\.)", re.IGNORECASE)
#     def _impl(entry):
#         return regex.match(entry)["domain"]
#     return _impl
# get_domain_name = get_domain_name()
