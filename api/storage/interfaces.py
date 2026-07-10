from abc import ABC, abstractmethod
from typing import BinaryIO, List, Optional


class IStorageProvider(ABC):
    """
    Base interface for all storage providers.
    Every provider (Supabase, R2, etc.) must implement this contract.
    """

    @abstractmethod
    def upload_file(
        self,
        bucket: str,
        remote_path: str,
        file: BinaryIO,
        *,
        upsert: bool = True,
        content_type: Optional[str] = None,
    ):
        """Upload a file."""
        raise NotImplementedError

    @abstractmethod
    def download_file(
        self,
        bucket: str,
        remote_path: str,
    ) -> bytes:
        """Download a file."""
        raise NotImplementedError

    @abstractmethod
    def delete_file(
        self,
        bucket: str,
        remote_path: str,
    ):
        """Delete a file."""
        raise NotImplementedError

    @abstractmethod
    def list_buckets(self) -> List[str]:
        """Return all available buckets."""
        raise NotImplementedError

    @abstractmethod
    def create_bucket(
        self,
        bucket: str,
        public: bool = False,
    ):
        """Create a new bucket."""
        raise NotImplementedError

    @abstractmethod
    def get_url(
        self,
        bucket: str,
        remote_path: str,
        expires_in: Optional[int] = None,
    ) -> str:
        """
        Return a URL.

        If expires_in is None:
            return public URL.

        Otherwise:
            return signed URL.
        """
        raise NotImplementedError