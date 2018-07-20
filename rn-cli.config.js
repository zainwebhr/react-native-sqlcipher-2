const path = require('path')

module.exports = {
  getProjectRoots: () => [
    path.join(__dirname, 'test'),
    __dirname,
  ]
}