import yaml
from argon2 import PasswordHasher
from argon2.low_level import Type

# Matches Authelia's expected format: $argon2id$v=19$m=65536,t=3,p=4$<salt>$<hash>
_hasher = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=4, hash_len=32, salt_len=16, type=Type.ID)


def argon2id_hash(password):
    return _hasher.hash(password)


def hash_authelia_users(raw_yaml):
    data = yaml.safe_load(raw_yaml)
    for user in data["users"].values():
        user["password"] = argon2id_hash(user["password"])
    return yaml.safe_dump(data, default_flow_style=False, sort_keys=False)


class FilterModule(object):
    def filters(self):
        return {
            "argon2id_hash": argon2id_hash,
            "hash_authelia_users": hash_authelia_users,
        }
