use crate::*;

#[derive(Default, PartialEq, Clone, Copy)]
pub enum MapData {
    #[default]
    Padding,
    Chunk(u32), // Chunk ID
    Block(u32), // Layer
    Tail(u32),  // Next index
}
impl MapData {
    pub fn is_padding(&self) -> bool {
        matches!(self, Self::Padding)
    }
    pub fn is_chunk(&self) -> bool {
        matches!(self, Self::Chunk(_))
    }
    pub fn is_block(&self) -> bool {
        matches!(self, Self::Block(_))
    }
    pub fn is_tail(&self) -> bool {
        matches!(self, Self::Tail(_))
    }
    pub fn pack(&self) -> MapDataPacked {
        match self {
            Self::Padding => MapDataPacked::default(),
            Self::Chunk(id) => {
                assert!(*id < (1 << 30), "Chunk ID too large: {}", id);
                MapDataPacked {
                    data: id << 2 | 0b01,
                }
            }
            Self::Block(layer) => {
                assert!(*layer < (1 << 30), "Layer too large: {}", layer);
                MapDataPacked {
                    data: layer << 2 | 0b10,
                }
            }
            Self::Tail(next_index) => {
                assert!(
                    *next_index < (1 << 30),
                    "Next index too large: {}",
                    next_index
                );
                MapDataPacked {
                    data: next_index << 2 | 0b11,
                }
            }
        }
    }
    pub fn get_next_index(&self) -> Option<u32> {
        // let a = crate::unpack!(self, Self::Tail(next_index));
        match self {
            Self::Tail(next_index) => Some(*next_index),
            _ => None,
        }
    }
    pub fn is_start_chunk(&self) -> bool {
        matches!(self, Self::Chunk(data) if data&0b100==0)
    }
    pub fn is_chunk_data(&self) -> bool {
        matches!(self, Self::Chunk(data) if data&0b100!=0)
    }
    pub fn chunk_data(&self) -> Option<u32> {
        if self.is_chunk_data() {
            match self {
                Self::Chunk(data) => Some(data >> 2),
                _ => unreachable!(),
            }
        } else {
            None
        }
    }
}

#[derive(ShaderType, Default, PartialEq, Clone, Copy)]
pub struct MapDataPacked {
    // 2 first bits = type:
    // 00=padding
    // 01=chunk
    // 10=block
    // 11=Tail
    pub data: u32,
}
impl MapDataPacked {
    pub fn unpack(&self) -> Option<MapData> {
        match self.data & 0b11 {
            0b00 => Some(MapData::Padding),
            0b01 => Some(MapData::Chunk(self.data >> 2)),
            0b10 => Some(MapData::Block(self.data >> 2)),
            0b11 => Some(MapData::Tail(self.data >> 2)),
            _ => unreachable!(),
        }
    }
}
impl std::fmt::Debug for MapDataPacked {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // self.unpack().map_or(
        //     writeln!(f, "Invalid MapDataPacked: {:b}", self.data),
        //     |data| writeln!(f, "{:?}", data),
        // )
        write!(f, "{:?}", self.unpack().unwrap())
    }
}

impl std::fmt::Debug for MapData {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MapData::Padding => write!(f, "Padding"),
            MapData::Chunk(id) => write!(f, "Chunk({})", id),
            MapData::Block(layer) => write!(f, "Block({})", layer),
            MapData::Tail(next_idx) => write!(f, "Tail({})", next_idx),
        }
    }
}