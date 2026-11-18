// Sắp xếp danh sách Thiết lập người dùng (góp ý của nhà trường, 2026-11-18).

/** Thứ tự danh sách người dùng: mặc định, tên, tổ chuyên môn hoặc chức vụ (cấp cao trước). */
export function sortUsersBy(users, mode, departments, positions) {
  if (mode === 'default') return users;
  const byName = (a, b) => (a.name || a.email || '').localeCompare(b.name || b.email || '', 'vi');
  const departmentName = (u) => departments.find((d) => d._id === u.departmentId)?.name || '';
  const position = (u) => positions.find((p) => p._id === u.positionId);
  const positionRank = (a, b) => {
    const pa = position(a);
    const pb = position(b);
    if (!pa || !pb) return (pa ? 0 : 1) - (pb ? 0 : 1); // chưa gán chức vụ xuống cuối
    return (pb.level || 0) - (pa.level || 0) || pa.name.localeCompare(pb.name, 'vi');
  };
  const departmentRank = (a, b) => {
    const da = departmentName(a);
    const db = departmentName(b);
    if (!da || !db) return (da ? 0 : 1) - (db ? 0 : 1); // chưa gán tổ xuống cuối
    return da.localeCompare(db, 'vi');
  };
  const compare = {
    name: byName,
    department: (a, b) => departmentRank(a, b) || positionRank(a, b) || byName(a, b),
    position: (a, b) => positionRank(a, b) || departmentRank(a, b) || byName(a, b),
  }[mode];
  return compare ? [...users].sort(compare) : users;
}
