from typing import Dict, Type

from .interfaces import IStorageProvider


class StorageFactory:
    _providers: Dict[str, Type[IStorageProvider]] = {}

    @classmethod
    def register(cls, name: str, provider: Type[IStorageProvider]) -> None:
        cls._providers[name.lower()] = provider

    @classmethod
    def create(cls, name: str, *args, **kwargs) -> IStorageProvider:
        provider = cls._providers.get(name.lower())

        if provider is None:
            available = ", ".join(sorted(cls._providers.keys()))
            raise ValueError(
                f"Unknown storage provider '{name}'. "
                f"Available providers: {available}"
            )

        return provider(*args, **kwargs)