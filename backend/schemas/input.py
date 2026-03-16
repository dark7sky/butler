from pydantic import BaseModel
from datetime import datetime

class ManualInputBase(BaseModel):
    key_name: str
    value: float

class ManualInputCreate(ManualInputBase):
    pass

class ManualInputResponse(ManualInputBase):
    id: int
    updated_at: datetime | None = None
    
    class Config:
        from_attributes = True
