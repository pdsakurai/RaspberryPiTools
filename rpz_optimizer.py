import re
from urllib import request
from datetime import datetime, timedelta, timezone
from argparse import ArgumentParser
import tempfile
import os
import shutil


class ZoneFile:
    def __init__(self, source_url, primary_name_server, hostmaster_email_address):
        self.source_url = source_url
        self.primary_name_server = primary_name_server
        self.hostmaster_email_address = hostmaster_email_address.replace("@", "/.")

    def _generate_header(self):
        yield f"; Source: {self.source_url}\n"

        today = datetime.now(timezone(timedelta(hours=8))).replace(microsecond=0)
        yield f"; Last modified: {today.isoformat()}\n\n"

        time_to_ = {
            "refresh": int(timedelta(days=1).total_seconds()),
            "retry": int(timedelta(minutes=1).total_seconds()),
            "expire": int(timedelta(days=30).total_seconds()),
            "expire NXDOMAIN cache": int(timedelta(seconds=30).total_seconds()),
            "expire SOA": int(timedelta(hours=1).total_seconds()),
        }

        yield f"$TTL {time_to_['expire SOA']}\n"
        yield f"@ IN SOA {self.primary_name_server}. {self.hostmaster_email_address}. (\n"
        yield f"         {today.strftime('%y%m%d%H%M')}\n"
        yield f"         {time_to_['refresh']}\n"
        yield f"         {time_to_['retry']}\n"
        yield f"         {time_to_['expire']}\n"
        yield f"         {time_to_['expire NXDOMAIN cache']} )\n"
        yield f" NS localhost.\n\n"

    def _generate_rpz_rules(self):
        with request.urlopen(self.source_url) as src_file:
            regex = re.compile(r"^\w")
            is_valid_rpz_trigger_rule = lambda entry: regex.match(entry)
            decoded_lines = (line_in_binary.decode() for line_in_binary in src_file)
            yield from (
                line for line in decoded_lines if is_valid_rpz_trigger_rule(line)
            )

    def generate(self):
        yield from self._generate_header()
        yield from self._generate_rpz_rules()


def get_arguments():
    arg_parser = ArgumentParser()
    arg_parser.add_argument("-s", "--source_url", required=True, type=str)
    arg_parser.add_argument("-d", "--destination_file", required=True, type=str)
    arg_parser.add_argument("-n", "--name_server", required=True, type=str)
    arg_parser.add_argument("-e", "--email_address", required=True, type=str)
    args = arg_parser.parse_args()
    return (
        args.source_url,
        args.destination_file,
        args.name_server,
        args.email_address,
    )


if __name__ == "__main__":
    source_url, destination_file, name_server, email_address = get_arguments()
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_file_fd, temp_file_path = tempfile.mkstemp(text=True, dir=temp_dir)
        with os.fdopen(temp_file_fd, mode="w") as temp_file:
            temp_file.writelines(
                ZoneFile(source_url, name_server, email_address).generate()
            )
        shutil.move(temp_file_path, destination_file)

# def get_domain_name():
#     regex = re.compile(r"^(?P<domain>(?=\w|\*\.).+)(\s+CNAME\s+\.)", re.IGNORECASE)
#     def _impl(entry):
#         return regex.match(entry)["domain"]
#     return _impl
# get_domain_name = get_domain_name()
