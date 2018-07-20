import SQLite, { encodeName as encodeNameImpl } from './src'

if (!process.nextTick) {
  process.nextTick = function (callback) {
    setTimeout(callback, 0);
  };
}

export default SQLite;
export const encodeName = encodeNameImpl;
