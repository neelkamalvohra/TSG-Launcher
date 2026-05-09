from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from ..database import get_db
from ..deps import get_current_user
from ..models import User, Tile
from ..schemas import MeResponse, GroupSummary, TileOut

router = APIRouter(prefix="/me", tags=["me"])


@router.get("", response_model=MeResponse)
def get_me(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    group_summaries = [GroupSummary(pk=str(g.id), name=g.name) for g in user.groups]

    if user.is_superadmin:
        # Superadmins see all tiles
        all_tiles = db.query(Tile).order_by(Tile.name).all()
        tiles = [_tile_out(t) for t in all_tiles]
    else:
        # Collect tiles from all user groups, dedup by slug
        seen: set[str] = set()
        tiles: list[TileOut] = []
        for group in user.groups:
            for tile in group.tiles:
                if tile.slug not in seen:
                    seen.add(tile.slug)
                    tiles.append(_tile_out(tile))
        tiles.sort(key=lambda t: t.name)

    return MeResponse(
        pk=str(user.id),
        username=user.username,
        email=user.email,
        name=user.name,
        groups=group_summaries,
        tiles=tiles,
    )


def _tile_out(t: Tile) -> TileOut:
    return TileOut(
        pk=str(t.id),
        name=t.name,
        slug=t.slug,
        meta_launch_url=t.meta_launch_url,
        meta_icon=t.meta_icon,
        meta_description=t.meta_description,
        quick_panel=t.quick_panel,
    )
