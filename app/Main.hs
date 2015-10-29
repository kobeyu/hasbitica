{-# LANGUAGE DeriveDataTypeable  #-}
{-# LANGUAGE ScopedTypeVariables #-}
module Main where

import           Control.Lens               ((&), (.~), (^.))
import           Data.Aeson                 (FromJSON, decode,encode)
import qualified Data.ByteString.Lazy.Char8 as B
import           Data.Maybe                 (catMaybes, mapMaybe)
import           Data.Time.Clock            (getCurrentTime)
import           Hasbitica.Api
import           Hasbitica.LensStuff
import           Hasbitica.Settings         (getApiFromSettings)
import           Servant.Common.Req         (responseBody)
import           System.Console.CmdArgs
import           System.Directory           (getHomeDirectory)
import           System.FilePath.Posix      ((</>))

data HasbiticaCli = New { newTodoText :: String }
               | List
               | ListAll
               | Done { guid :: String }
               | Delete { guid :: String }
                 deriving (Show, Data, Typeable)

examples = [ New {newTodoText = "Buy milk" &= help "The text of the new todo" }
           , List &= help "List all not-done todos"
           , ListAll &= help "List all todos"
           , Done "<GUID>" &= help "Mark todo with guid X as done"
           , Delete "<GUID>" &= help "Delete todo X"]
             &= program "hasbitica-cli"

main :: IO ()
main = do
       x <- cmdArgs (modes examples)
       (Just key) <- getApiFromSettings
       case x of
         New x -> addTask key x >>= putStrLn
         List -> getAllNotDoneTodos >>= mapM_ (putStrLn . (\(a,b) -> a++" "++b))
         ListAll -> getAllTodos >>= mapM_ print 
         Done x -> doneTask key x >>= putStrLn
         Delete x -> runHabitica (deleteTask x key) >>= print

addTask :: HabiticaApiKey -> String -> IO String
addTask k t = do
  x <- runHabitica $ postTask (todo t) k
  case x of
    Left err -> return (B.unpack $ responseBody err)
    Right _ -> return "OK"

doneTask :: HabiticaApiKey -> String -> IO String
doneTask k t = do
  x <- runHabitica $ getTask t k
  now <- getCurrentTime
  case x of
    Left x -> return . show $ x
    Right (TaskTodo x) -> do
      let newTask = x & todoCompleted .~ True
                      & todoDateCompleted .~ Just now
      fmap show . runHabitica . updateTask t (TaskTodo newTask) $ k
    Right x -> return ("Not a todo: "++show x)

getAllTodos :: IO [Todo]
getAllTodos = do
  (Just k) <- getApiFromSettings
  ans <- runHabitica $ getTasks k
  case ans of
    Left err -> return []
    Right tasks -> return  (mapMaybe fromTask tasks)

getAllNotDoneTodos :: IO [(String,String)]
getAllNotDoneTodos = do
  (Just k) <- getApiFromSettings
  tasks <- getTodos k
  case tasks of
    Left err -> return [("ERROR",show err)]
    Right tsks -> do
                  let x = map (\i -> (i^.todoBase . taskId , i^.todoBase . text)) tsks
                  return x

