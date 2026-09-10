import { useMemo, useState } from 'react';
import { useQuery } from 'convex/react';
import { anyApi } from 'convex/server';
import DutyWorkspaceTabs, { OfficialDutyHeader } from './DutyWorkspaceTabs';
import {
  buildSharedScheduleRows,
  shiftScheduleAnchor,
  toIsoDate,
} from './sharedDutySchedule.js';
import './sharedDutySchedule.css';

export default function SharedDutyScheduleView({ onChooseView }) {
  const [mode, setMode] = useState('week');
  const [anchorIso, setAnchorIso] = useState(() => toIsoDate(new Date()));
  const rangePreview = useMemo(() => buildSharedScheduleRows(mode, anchorIso, []).range, [mode, anchorIso]);
  const data = useQuery(anyApi.duties.sharedSchedule, {
    startDate: rangePreview.startIso,
    endDate: rangePreview.endIso,
  });
  const built = useMemo(
    () => buildSharedScheduleRows(mode, anchorIso, data?.events || []),
    [mode, anchorIso, data?.events],
  );

  const downloading = async () => {
    const { downloadSharedDutySchedulePdf: savePdf } = await import('./sharedDutySchedulePdf.js');
    savePdf(built);
  };

  return (
    <section className="work-management duty-workspace lct-shared-view">
      <DutyWorkspaceTabs view="shared" onChoose={onChooseView} />
      <div className="lct-shared-toolbar">
        <div className="lct-shared-toolbar-center">
          <div className="lct-period-nav" role="group" aria-label="Chọn kỳ">
            <button type="button" onClick={() => setAnchorIso((current) => shiftScheduleAnchor(mode, current, -1))} aria-label="Kỳ trước">
              ‹
            </button>
            <button type="button" className="lct-today" onClick={() => setAnchorIso(toIsoDate(new Date()))}>
              Hôm nay
            </button>
            <button type="button" onClick={() => setAnchorIso((current) => shiftScheduleAnchor(mode, current, 1))} aria-label="Kỳ sau">
              ›
            </button>
          </div>
          <div className="lct-mode-switch" role="group" aria-label="Kiểu hiển thị">
            <button type="button" className={mode === 'week' ? 'is-active' : undefined} onClick={() => setMode('week')}>
              Tuần
            </button>
            <button type="button" className={mode === 'month' ? 'is-active' : undefined} onClick={() => setMode('month')}>
              Tháng
            </button>
          </div>
        </div>
        <button
          type="button"
          className="work-primary-button lct-download"
          disabled={data === undefined}
          onClick={() => void downloading()}
        >
          Tải PDF
        </button>
      </div>

      {data === undefined ? (
        <p className="lct-loading">Đang dựng lịch công tác chung…</p>
      ) : (
        <article className="lct-sheet" aria-label={built.range.title}>
          <OfficialDutyHeader title={built.range.title} />
          <table className="lct-table">
            <colgroup>
              <col className="lct-col-day" />
              <col className="lct-col-time" />
              <col className="lct-col-content" />
              <col className="lct-col-place" />
              <col className="lct-col-people" />
            </colgroup>
            <thead>
              <tr>
                <th>Ngày</th>
                <th>Thời gian</th>
                <th>Nội dung</th>
                <th>Địa điểm</th>
                <th>Thành phần</th>
              </tr>
            </thead>
            <tbody>
              {built.rows.map((row, index) => (
                <tr key={`${row.dayIso}-${row.eventId || 'empty'}-${index}`}>
                  {row.showDay ? (
                    <th scope="row" rowSpan={row.rowSpan}>{row.dayLabel}</th>
                  ) : null}
                  <td>{row.time}</td>
                  <td>{row.content}</td>
                  <td>{row.location}</td>
                  <td>{row.participants}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </article>
      )}
    </section>
  );
}
