namespace TryWorld.Scripts.Blocks;

public class MicroBlockData
{
    // 64 个微块：占用 + 类型
    // occupancy bitmask: 1 = 存在
    public ulong Occupancy;
    public byte[] Types; // 长度 64，对应 BlockType ID

    public MicroBlockData(byte initialType)
    {
        Types = new byte[64];
        Occupancy = 0UL;
        for (int i = 0; i < 64; i++)
        {
            Types[i] = initialType;
            Occupancy |= (1UL << i);
        }
    }

    public static int ToIndex(int x, int y, int z) => x + y * 4 + z * 16;

    public bool Has(int x, int y, int z)
    {
        int idx = ToIndex(x, y, z);
        return (Occupancy & (1UL << idx)) != 0;
    }

    public byte Get(int x, int y, int z)
    {
        int idx = ToIndex(x, y, z);
        return Types[idx];
    }

    public void Set(int x, int y, int z, byte type)
    {
        int idx = ToIndex(x, y, z);
        Types[idx] = type;
        Occupancy |= (1UL << idx);
    }

    public void Remove(int x, int y, int z)
    {
        int idx = ToIndex(x, y, z);
        Occupancy &= ~(1UL << idx);
        Types[idx] = 0;
    }

    public bool IsUniform(out byte type)
    {
        // 若全为空则 uniform=false; 若有一个类型不同也返回 false
        type = 0;
        ulong occ = Occupancy;
        if (occ == 0UL) return false;

        // 找到第一个位
        int firstIndex = TrailingZeroCount(occ);
        byte baseType = Types[firstIndex];

        // 遍历所有 set 位判断是否类型一致
        ulong temp = occ;
        while (temp != 0)
        {
            int idx = TrailingZeroCount(temp);
            if (Types[idx] != baseType) return false;
            temp &= ~(1UL << idx);
        }
        type = baseType;
        return true;
    }

    private static int TrailingZeroCount(ulong value)
    {
        if (value == 0) return 64;
        int count = 0;
        while ((value & 1) == 0)
        {
            value >>= 1;
            count++;
        }
        return count;
    }
}