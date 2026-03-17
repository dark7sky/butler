from sqlalchemy import (
    BigInteger,
    Boolean,
    Column,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
    Numeric,
    String,
)
from sqlalchemy.sql import func

from db.database import Base


class ManualInput(Base):
    __tablename__ = "manual_inputs"

    id = Column(Integer, primary_key=True, index=True)
    key_name = Column(String(255), unique=True, index=True, nullable=False)
    value = Column(Numeric, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class SystemSetting(Base):
    __tablename__ = "system_settings"

    id = Column(Integer, primary_key=True, index=True)
    setting_key = Column(String(100), unique=True, index=True, nullable=False)
    setting_value = Column(JSON, nullable=False)
    updated_at = Column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
    )


class Account(Base):
    __tablename__ = "accounts"

    account_key = Column(String, primary_key=True)
    company = Column(String)
    type = Column(String)
    name = Column(String)
    memo = Column(String, nullable=False, server_default="")
    is_special = Column(Boolean, nullable=False, server_default="false")
    is_active = Column(Boolean, nullable=False, server_default="true")
    created_at = Column(DateTime(timezone=True), nullable=False, server_default=func.now())
    updated_at = Column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        onupdate=func.now(),
    )


class AccountBalanceHistory(Base):
    __tablename__ = "account_balance_history"

    account_key = Column(
        String,
        ForeignKey("accounts.account_key", ondelete="CASCADE"),
        primary_key=True,
    )
    recorded_at = Column(DateTime(timezone=True), primary_key=True)
    balance = Column(BigInteger, nullable=False)
    source = Column(String(100), nullable=False)


class PortfolioBalanceHistory(Base):
    __tablename__ = "portfolio_balance_history"

    recorded_at = Column(DateTime(timezone=True), primary_key=True)
    balance = Column(BigInteger, nullable=False)


class PortfolioDayDiff(Base):
    __tablename__ = "portfolio_daydiff"

    balance_date = Column(Date, primary_key=True)
    balance = Column(BigInteger, nullable=False)


class PortfolioMonthDiff(Base):
    __tablename__ = "portfolio_monthdiff"

    balance_date = Column(Date, primary_key=True)
    balance = Column(BigInteger, nullable=False)
