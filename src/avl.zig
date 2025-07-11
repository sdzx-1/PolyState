//The AVL tree implemented using array.
//https://www.geeksforgeeks.org/c/c-program-to-implement-avl-tree/
//

pub fn Node(Ty: type) type {
    return struct {
        key: u32,
        data: Ty,
        left: i32,
        right: i32,
        height: i32,
    };
}
pub fn AVL(comptime max_len: usize, Ty: type) type {
    return struct {
        len: i32 = 0,
        nodes: [max_len]Node(Ty) = undefined,

        const Self = @This();

        pub fn search(self: *const Self, root: i32, key: u32) ?Ty {
            if (root == -1) return null;
            const node = self.nodes[@as(usize, @intCast(root))];
            if (key == node.key) return node.data;
            if (key < node.key) return self.search(node.left, key);
            if (key > node.key) return self.search(node.right, key);
            return null;
        }
        pub fn insert(self: *Self, node: i32, key: u32, data: Ty) i32 {
            // 1. Perform standard BST insertion
            if (node == -1) return self.createNode(key, data);

            if (key < self.access(node).key) {
                self.access(node).left = self.insert(self.access(node).left, key, data);
            } else if (key > self.access(node).key) {
                self.access(node).right = self.insert(self.access(node).right, key, data);
            } else {
                return node;
            }

            // 2. Update height of this ancestor node

            self.access(node).height = @as(i32, 1) + @max(
                self.getHeight(self.access(node).left),
                self.getHeight(self.access(node).right),
            );

            // 3. Get the balance factor of this ancestor node to
            // check whether this node became unbalanced
            const balance = self.getBalanceFactor(node);

            // 4. If the node becomes unbalanced, then there are 4
            // cases
            // Left Left Case
            if (balance > 1 and key < self.access(self.access(node).left).key) {
                return self.rightRotate(node);
            }

            // Right Right Case
            if (balance < -1 and key > self.access(self.access(node).right).key) {
                return self.leftRotate(node);
            }

            // Left Right Case
            if (balance > 1 and key > self.access(self.access(node).left).key) {
                self.access(node).left = self.leftRotate(self.access(node).left);
                return self.rightRotate(node);
            }

            // Right Left Case

            if (balance < -1 and key < self.access(self.access(node).right).key) {
                self.access(node).right = self.rightRotate(self.access(node).right);
                return self.leftRotate(node);
            }

            // Return the (unchanged) node pointer
            return node;
        }

        fn access(self: *Self, i: i32) *(Node(Ty)) {
            return &self.nodes[@as(usize, @intCast(i))];
        }

        // Function to get height of the node

        fn getHeight(self: *Self, n: i32) i32 {
            if (n == -1) {
                return 0;
            } else {
                return self.access(n).height;
            }
        }

        // Function to create a new node
        //     node->height = 1; // New node is initially added at leaf

        fn createNode(self: *Self, key: u32, data: Ty) i32 {
            const curr = self.len;
            if (curr >= self.nodes.len) unreachable; //The used state exceeds the estimated maximum. You should increase the value of max_len
            self.len += 1;
            self.access(curr).* = .{ .key = key, .data = data, .left = -1, .right = -1, .height = 1 };
            return curr;
        }

        // Function to get balance factor of a node

        fn getBalanceFactor(self: *Self, n: i32) i32 {
            if (n == -1) return 0;
            return self.getHeight(self.access(n).left) - self.getHeight(self.access(n).right);
        }

        fn rightRotate(self: *Self, y: i32) i32 {
            // Right rotation function
            const x = self.access(y).left;
            const t2 = self.access(x).right;

            // Perform rotation
            self.access(x).right = y;
            self.access(y).left = t2;

            // Update heights
            self.access(y).height = @max(
                self.getHeight(self.access(y).left),
                self.getHeight(self.access(y).right),
            ) + @as(i32, 1);

            self.access(x).height = @max(
                self.getHeight(self.access(x).left),
                self.getHeight(self.access(x).right),
            ) + @as(i32, 1);

            return x;
        }

        fn leftRotate(self: *Self, x: i32) i32 {
            // Left rotation function
            const y = self.access(x).right;
            const t2 = self.access(y).left;

            // Perform rotation
            self.access(y).left = x;
            //     x->right = T2;
            self.access(x).right = t2;

            // Update heights

            self.access(x).height = @max(
                self.getHeight(self.access(x).left),
                self.getHeight(self.access(x).right),
            ) + @as(i32, 1);

            self.access(y).height = @max(
                self.getHeight(self.access(y).left),
                self.getHeight(self.access(y).right),
            ) + @as(i32, 1);

            //     return y;
            return y;
        }

        fn inOrder(self: *Self, root: i32) void {
            if (root != -1) {
                self.inOrder(self.access(root).left);
                std.debug.print("{d} ", .{self.access(root).key});
                self.inOrder(self.access(root).right);
            }
        }
    };
}

test "avl" {
    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;
        try std.posix.getrandom(std.mem.asBytes(&seed));
        break :blk seed;
    });
    const rand = prng.random();

    const ty_arr: []const type = &.{ i32, i64, u32, u64 };
    const len_arr: []const usize = &.{ 0, 1, 2, 3, 4, 6, 8, 10, 200, 450, 780, 800, 1000 };

    inline for (ty_arr) |Ty| {
        inline for (len_arr) |len| {
            var tmp_arr: [len]struct { u32, Ty } = undefined;
            for (0..len) |i| {
                tmp_arr[i] = .{ @as(u32, @intCast(i)), @as(Ty, @intCast(i + 1)) };
            }

            for (0..len) |_| {
                const id_a: usize = @intCast(rand.intRangeAtMost(Ty, 0, len - 1));
                const id_b: usize = @intCast(rand.intRangeAtMost(Ty, 0, len - 1));
                const tmp = tmp_arr[id_a];
                tmp_arr[id_a] = tmp_arr[id_b];
                tmp_arr[id_b] = tmp;
            }

            var root: i32 = -1;
            var avl: AVL(len, Ty) = .{};

            for (0..len) |i| {
                const tmp = tmp_arr[i];
                root = avl.insert(root, tmp.@"0", tmp.@"1");
            }

            for (0..len) |i| {
                const key: u32 = @intCast(i);
                const val: u32 = @intCast(avl.search(root, key).?);
                std.debug.assert((key + 1) == val);
            }
        }
    }
}

const std = @import("std");
